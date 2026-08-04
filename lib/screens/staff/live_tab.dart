import 'dart:async';

import 'package:apivideo_live_stream/apivideo_live_stream.dart';
import 'package:flutter/material.dart';

import '../../services/staff_api.dart';
import '../../services/comment_service.dart';
import '../../widgets/glass.dart';
import '../../theme.dart';

/// Эфир: превью камеры, заголовок и кнопка «Начать эфир» (RTMP на сервер).
class LiveTab extends StatefulWidget {
  const LiveTab({super.key});

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
  ApiVideoLiveStreamController? _controller;
  String? _cameraError;
  bool _streaming = false;
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
      onConnectionSuccess: () {
        if (mounted) setState(() {});
      },
      onConnectionFailed: (e) {
        if (!mounted) return;
        setState(() => _streaming = false);
        _stopTimer();
        _snack('Не удалось подключиться к серверу эфира: $e');
      },
      onDisconnection: () {
        if (!mounted) return;
        setState(() => _streaming = false);
        _stopTimer();
      },
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

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
  }

  void _stopComments() {
    _commentPoll?.cancel();
    _commentPoll = null;
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
        await c.stopStreaming();
        setState(() => _streaming = false);
        _stopTimer();
        _stopComments();
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
        // Заголовок эфира — на сервер (не критично, если не дойдёт).
        await const StaffApi().setLiveTitle(_titleCtrl.text.trim());
        await c.startStreaming(
            streamKey: cfg.streamKey, url: cfg.rtmpUrl);
        setState(() => _streaming = true);
        _startTimer();
        _startComments();
      }
    } catch (e) {
      _snack('Ошибка эфира: $e');
      setState(() => _streaming = false);
      _stopTimer();
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
    _stopTimer();
    _stopComments();
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
                _liveBadge(),
              ],
            ),
          ),
        ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PulsingDot(color: Colors.white, size: 7),
          const SizedBox(width: 6),
          Text('LIVE $_clock',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ],
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
