import 'dart:async';

import 'package:apivideo_live_stream/apivideo_live_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../services/staff_api.dart';
import '../../services/comment_service.dart';
import '../../services/live_service.dart';
import '../../widgets/glass.dart';
import '../../theme.dart';

/// Состояние эфира. Раньше здесь был один флаг `_streaming`, но с появлением
/// переподключения состояний стало четыре, и на флагах логика разъезжалась:
/// «идёт ли эфир» и «есть ли связь» — разные вопросы, и во время
/// переподключения ответы на них расходятся.
enum _LiveState {
  /// Эфира нет: экран настройки, камера может быть включена для превью.
  idle,

  /// Отправили startStreaming, ждём подтверждения от сервера.
  connecting,

  /// Связь есть, поток идёт.
  live,

  /// Связь потеряна не по воле устаза — пробуем вернуться сами.
  reconnecting,
}

/// Эфир: превью камеры, заголовок и кнопка «Начать эфир» (RTMP на сервер).
class LiveTab extends StatefulWidget {
  const LiveTab({super.key});

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> with WidgetsBindingObserver {
  ApiVideoLiveStreamController? _controller;
  String? _cameraError;
  _LiveState _state = _LiveState.idle;
  bool _busy = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  Timer? _commentPoll;
  final _scrollCtrl = ScrollController();
  List<LiveComment> _comments = [];
  final _titleCtrl = TextEditingController(text: 'Прямой эфир устаза');

  /// Камеру включаем только по явному нажатию. Раньше она поднималась при
  /// открытии кабинета, и приложение просило камеру с микрофоном у устаза,
  /// который зашёл всего лишь поправить название курса.
  bool _cameraOn = false;

  // ── Переподключение ────────────────────────────────────────────────────
  //
  // Сервер сворачивает эфир, если данные от телефона не идут 11 секунд
  // (замерено). Раньше обрыв означал конец трансляции навсегда: обработчик
  // лишь ставил флаг, и устаз, ведущий урок с телефона на подставке, узнавал
  // об этом сильно позже. Теперь приложение возвращается само.

  /// Паузы между попытками. Растут, чтобы не молотить сеть впустую, но
  /// первая короткая — обычные провалы связи длятся считанные секунды.
  static const _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];

  int _retry = 0;
  Timer? _retryTimer;

  /// Сколько учеников смотрит. Устаз спрашивает сервер, а не отмечается
  /// сам: иначе он посчитал бы себя зрителем собственного эфира.
  int _viewers = 0;
  Timer? _viewersPoll;

  /// Устаз нажал «Завершить эфир». Единственное, что отличает штатный конец
  /// от обрыва: с точки зрения плагина оба выглядят как onDisconnection.
  bool _userStopped = false;

  /// Данные публикации кэшируем с первого старта. Перезапрашивать их при
  /// обрыве нельзя: связи в этот момент как раз и нет, запрос к серверу
  /// упал бы ровно тогда, когда переподключение нужнее всего.
  StreamConfig? _cfg;

  /// Текст на красной карточке экрана настройки — чтобы устаз, вернувшись
  /// к телефону, увидел, что эфир прервался, а не гадал.
  String? _dropNotice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Возвращение приложения из фона. Пока телефон в фоне таймеры Flutter
  /// не тикают, поэтому отложенная попытка переподключения могла проспать
  /// весь этот срок. Как только устаз вернулся к экрану — пробуем сразу.
  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.resumed &&
        _state == _LiveState.reconnecting &&
        !_userStopped) {
      _retryTimer?.cancel();
      _attemptReconnect();
    }
  }

  Future<void> _initCamera() async {
    if (_cameraOn) return;
    setState(() {
      _cameraOn = true;
      _cameraError = null;
    });
    final c = ApiVideoLiveStreamController(
      initialAudioConfig: AudioConfig(),
      // 480p @ 1.2 Мбит/с — надёжно для мобильного аплинка, без рывков.
      initialVideoConfig: VideoConfig(
          bitrate: 1200000,
          resolution: Resolution.RESOLUTION_480,
          fps: 30),
      initialCameraPosition: CameraPosition.front,
      onConnectionSuccess: _onConnected,
      onConnectionFailed: _onConnectionFailed,
      onDisconnection: _onDisconnected,
    );
    try {
      await c.initialize();
      if (!mounted) return;
      setState(() => _controller = c);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError =
          'Камера недоступна: $e\n(на симуляторе камеры нет — проверьте на телефоне)');
    }
  }

  // ── Обработчики соединения ─────────────────────────────────────────────

  /// Связь установлена — и при первом старте, и после переподключения.
  void _onConnected() {
    if (!mounted) return;
    final wasReconnecting = _state == _LiveState.reconnecting;
    _retryTimer?.cancel();
    setState(() {
      _state = _LiveState.live;
      _retry = 0;
      _dropNotice = null;
    });
    if (wasReconnecting) _snack('Связь восстановлена, эфир продолжается');
  }

  /// Не удалось подключиться. Отличается от [_onDisconnected] тем, что
  /// соединения не было вовсе, — но лечится тем же повтором: в дороге
  /// «не подключилось» и «отвалилось» одинаково означают плохую сеть.
  void _onConnectionFailed(String e) {
    if (!mounted || _userStopped) return;
    _scheduleReconnect('Не удалось подключиться к серверу эфира');
  }

  /// Соединение разорвано. Штатное завершение приходит сюда же, поэтому
  /// первым делом смотрим на [_userStopped].
  void _onDisconnected() {
    if (!mounted) return;
    if (_userStopped) {
      setState(() => _state = _LiveState.idle);
      return;
    }
    _scheduleReconnect('Связь с сервером эфира потеряна');
  }

  // ── Переподключение ────────────────────────────────────────────────────

  /// Ставит следующую попытку в очередь либо сдаётся, если их больше нет.
  void _scheduleReconnect(String reason) {
    if (_retry >= _retryDelays.length) {
      _giveUp(reason);
      return;
    }
    final delay = _retryDelays[_retry];
    _retry++;
    setState(() => _state = _LiveState.reconnecting);
    // Вибрация на каждой попытке: телефон обычно на подставке, и это
    // единственный сигнал, который устаз заметит, не глядя на экран.
    HapticFeedback.heavyImpact();
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, _attemptReconnect);
  }

  Future<void> _attemptReconnect() async {
    if (!mounted || _userStopped || _state != _LiveState.reconnecting) return;
    final c = _controller;
    final cfg = _cfg;
    if (c == null || cfg == null) {
      _giveUp('Эфир прерван');
      return;
    }
    try {
      // Обрываем возможный подвисший сеанс: без этого плагин на некоторых
      // устройствах отказывается стартовать поверх незакрытого соединения.
      await c.stopStreaming();
      await c.startStreaming(streamKey: cfg.streamKey, url: cfg.rtmpUrl);
      // Успех подтвердит onConnectionSuccess. Если он не придёт, сервер
      // разорвёт соединение сам и мы вернёмся сюда следующей попыткой.
    } catch (e) {
      if (!mounted) return;
      _scheduleReconnect('Не удалось переподключиться');
    }
  }

  /// Попытки исчерпаны. Эфир закончен — говорим об этом громко.
  void _giveUp(String reason) {
    _retryTimer?.cancel();
    _stopTimer();
    _stopComments();
    WakelockPlus.disable();
    if (!mounted) return;
    setState(() {
      _state = _LiveState.idle;
      _retry = 0;
      _dropNotice = '$reason. Эфир остановлен — нажмите «Начать эфир», '
          'чтобы возобновить.';
    });
    // Звук и серия вибраций: устаз ведёт урок и на экран не смотрит.
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 400),
        () => HapticFeedback.heavyImpact());
    Future.delayed(const Duration(milliseconds: 800),
        () => HapticFeedback.heavyImpact());
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// «Эфир идёт» с точки зрения интерфейса: во время переподключения
  /// трансляция для устаза не закончилась, экран должен остаться прежним.
  bool get _streaming => _state != _LiveState.idle;

  void _startTimer() {
    _elapsed = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _startComments() {
    _loadComments();
    _commentPoll?.cancel();
    _commentPoll =
        Timer.periodic(const Duration(seconds: 4), (_) => _loadComments());
    // Зрителей опрашиваем реже комментариев: число меняется медленно,
    // а на сервере оно считается по живым сердцебиениям с окном в 45 секунд.
    _loadViewers();
    _viewersPoll?.cancel();
    _viewersPoll =
        Timer.periodic(const Duration(seconds: 8), (_) => _loadViewers());
  }

  void _stopComments() {
    _commentPoll?.cancel();
    _commentPoll = null;
    _viewersPoll?.cancel();
    _viewersPoll = null;
    _viewers = 0;
  }

  Future<void> _loadViewers() async {
    final n = await LiveService.viewers();
    if (!mounted || n == null || n == _viewers) return;
    setState(() => _viewers = n);
  }

  Future<void> _loadComments() async {
    final list = await CommentService.fetch();
    if (!mounted) return;
    // Список перевёрнут (reverse), поэтому «низ» = смещение 0.
    final atBottom =
        !_scrollCtrl.hasClients || _scrollCtrl.position.pixels <= 40;
    setState(() => _comments = list);
    if (atBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
      });
    }
  }

  Future<void> _toggle() async {
    final c = _controller;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (_streaming) {
        // Флаг ставим ДО остановки: onDisconnection прилетит немедленно,
        // и без него переподключение приняло бы штатный конец за обрыв
        // и подняло бы эфир заново.
        _userStopped = true;
        _retryTimer?.cancel();
        _retry = 0;
        await c.stopStreaming();
        setState(() => _state = _LiveState.idle);
        _stopTimer();
        _stopComments();
        await WakelockPlus.disable();
      } else {
        // Адрес и ключ публикации выдаёт сервер по токену: держать ключ в
        // сборке нельзя — приложение публичное, строку вытащат из бинарника
        // и вклинятся в эфир.
        final cfg = await const StaffApi().streamConfig();
        if (cfg == null) {
          _snack('Не удалось получить данные эфира — проверьте связь и вход');
          if (mounted) setState(() => _busy = false);
          return;
        }
        _cfg = cfg;
        _userStopped = false;
        _retry = 0;
        // Заголовок эфира — на сервер (не критично, если не дойдёт).
        await const StaffApi().setLiveTitle(_titleCtrl.text.trim());
        await c.startStreaming(
            streamKey: cfg.streamKey, url: cfg.rtmpUrl);
        setState(() {
          _state = _LiveState.connecting;
          _dropNotice = null;
        });
        _startTimer();
        _startComments();
        // Не даём экрану гаснуть. Без этого телефон на подставке блокируется
        // через минуту-другую, съёмка останавливается, и сервер сворачивает
        // эфир — самая частая причина обрыва, ничего общего с сетью.
        await WakelockPlus.enable();
      }
    } catch (e) {
      _snack('Ошибка эфира: $e');
      setState(() => _state = _LiveState.idle);
      _stopTimer();
      await WakelockPlus.disable();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _clock {
    final h = _elapsed.inHours.toString().padLeft(2, '0');
    final m = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _viewersPoll?.cancel();
    _stopTimer();
    _stopComments();
    // Уходя с вкладки, обязательно снимаем удержание экрана: иначе телефон
    // не гаснет и после эфира, и батарея садится незаметно для устаза.
    WakelockPlus.disable();
    _scrollCtrl.dispose();
    _controller?.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _streaming ? _liveLayout() : _setupLayout();
  }

  static const _hpad = EdgeInsets.symmetric(horizontal: 20);

  /// До старта эфира: превью на всю ширину, поле названия и кнопка.
  Widget _setupLayout() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: 14),
        Padding(padding: _hpad, child: _header()),
        const SizedBox(height: 14),
        Padding(padding: _hpad, child: _dropNoticeCard()),
        _cameraPreview(),
        const SizedBox(height: 16),
        Padding(padding: _hpad, child: _titleField()),
        const SizedBox(height: 16),
        Padding(padding: _hpad, child: _actionButton()),
        const SizedBox(height: 8),
        Padding(padding: _hpad, child: _hint()),
        const SizedBox(height: 20),
      ],
    );
  }

  /// Во время эфира: камера на весь экран (портрет), а поверх видео —
  /// значок LIVE сверху и лента комментариев + кнопка снизу.
  Widget _liveLayout() {
    final maxCommentsH = MediaQuery.of(context).size.height * 0.38;
    return Stack(
      fit: StackFit.expand,
      children: [
        _cameraCover(),
        // Верхний скрим + значок LIVE.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                const Text('Эфир',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const Spacer(),
                _viewersBadge(),
                const SizedBox(width: 8),
                _liveBadge(),
              ],
            ),
          ),
        ),
        if (_state == _LiveState.reconnecting)
          Positioned(top: 72, left: 16, right: 16, child: _reconnectBanner()),
        // Нижний скрим + комментарии + кнопка «Завершить эфир».
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 44, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.65),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxCommentsH),
                  child: _commentsOverlay(),
                ),
                const SizedBox(height: 12),
                _actionButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _liveBadge() {
    // Пока связи нет, значок серый и без слова LIVE: показывать красный
    // «в эфире» в момент, когда на сервер ничего не уходит, — обман.
    final connected = _state == _LiveState.live;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: connected ? Colors.red.shade700 : Colors.grey.shade700,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PulsingDot(color: Colors.white, size: 7),
          const SizedBox(width: 6),
          Text(connected ? 'LIVE $_clock' : 'НЕТ СВЯЗИ',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ],
      ),
    );
  }

  /// Число смотрящих. Показываем и ноль: устазу важно знать, что его пока
  /// никто не смотрит, — это повод подождать или позвать учеников.
  Widget _viewersBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility_outlined,
              size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text('$_viewers',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ],
      ),
    );
  }

  /// Баннер поверх картинки на время попыток вернуть связь.
  Widget _reconnectBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.orange.shade900,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Связь потеряна — восстанавливаю',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                  'Попытка $_retry из ${_retryDelays.length}. '
                  'Ученики видят паузу.',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Красная карточка на экране настройки: эфир оборвался, пока устаз
  /// не смотрел. Держится до следующего старта, снэкбар для этого не годится —
  /// он исчезает через несколько секунд.
  Widget _dropNoticeCard() {
    final text = _dropNotice;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 14, height: 1.35, color: Colors.white)),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              onPressed: () => setState(() => _dropNotice = null),
            ),
          ],
        ),
      ),
    );
  }

  /// Камера на весь экран без искажений (кроп по краям).
  Widget _cameraCover() => _preview(fit: BoxFit.cover);

  /// Превью без искажений: берём реальный размер видео с камеры, приводим
  /// к портрету и заполняем контейнер ([fit]). Не полагаемся на внутренний
  /// определитель ориентации плагина — на этом iPhone он плющит картинку.
  Widget _preview({required BoxFit fit}) {
    final c = _controller;
    if (c == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: _cameraOn
            ? Text(
                _cameraError ?? 'Запуск камеры…',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.75)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_outlined,
                      size: 40, color: Colors.white.withValues(alpha: 0.6)),
                  const SizedBox(height: 12),
                  Text(
                    'Камера включится, когда вы будете готовы вести эфир.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.75)),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _initCamera,
                    icon: const Icon(Icons.videocam, size: 18),
                    label: const Text('Включить камеру'),
                  ),
                ],
              ),
      );
    }
    return FutureBuilder<Size?>(
      future: c.videoSize,
      builder: (context, snap) {
        final s = snap.data ?? const Size(720, 1280);
        final w = s.width <= s.height ? s.width : s.height;
        final h = s.width <= s.height ? s.height : s.width;
        return ClipRect(
          child: FittedBox(
            fit: fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: w,
              height: h,
              // ignore: invalid_use_of_internal_member
              child: c.buildPreview(),
            ),
          ),
        );
      },
    );
  }

  /// Лента комментариев поверх видео (с тенью для читаемости).
  Widget _commentsOverlay() {
    if (_comments.isEmpty) {
      return Align(
        alignment: Alignment.bottomLeft,
        child: Text(
          'Комментарии учеников появятся здесь…',
          style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.85),
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 4)
              ]),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      // Прижимаем к низу: новые комментарии внизу, старые уходят вверх.
      reverse: true,
      padding: EdgeInsets.zero,
      itemCount: _comments.length,
      itemBuilder: (_, i) {
        final c = _comments[_comments.length - 1 - i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
              children: [
                TextSpan(
                    text: '${c.name}  ',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold)),
                TextSpan(text: c.text),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header() {
    return FadeSlideIn(
      offset: const Offset(-24, 0),
      child: Row(
        children: [
          const Text('Эфир',
              style:
                  TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (_streaming)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const PulsingDot(color: Colors.white, size: 7),
                  const SizedBox(width: 6),
                  Text('LIVE $_clock',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Превью на всю ширину, вертикальное 3:4 (экран настройки до старта).
  Widget _cameraPreview() {
    return FadeSlideIn(
      delay: const Duration(milliseconds: 120),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: _preview(fit: BoxFit.cover),
        ),
      ),
    );
  }

  Widget _titleField() {
    return FadeSlideIn(
      delay: const Duration(milliseconds: 220),
      child: TextField(
        controller: _titleCtrl,
        enabled: !_streaming,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          labelText: 'Название эфира',
          prefixIcon:
              const Icon(Icons.title, color: AppColors.gold, size: 20),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.3),
          labelStyle:
              TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.gold),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
        ),
      ),
    );
  }

  Widget _actionButton() {
    return FadeSlideIn(
      delay: const Duration(milliseconds: 320),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor:
                _streaming ? Colors.red.shade700 : AppColors.accentGreen,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: _controller == null || _busy ? null : _toggle,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Icon(
                  _streaming
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                  size: 22),
          label: Text(
            _streaming ? 'Завершить эфир' : 'Начать эфир',
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _hint() {
    return FadeSlideIn(
      delay: const Duration(milliseconds: 400),
      child: Text(
        'Эфир появится у всех учеников в приложении «Ирфан» через ~10 секунд после старта.',
        style: TextStyle(
            fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
      ),
    );
  }
}
