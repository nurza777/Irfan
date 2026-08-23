import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/auth_service.dart';
import '../services/chat_moderation.dart';
import '../services/comment_service.dart';
import '../services/live_service.dart';
import '../services/lang.dart';
import '../theme.dart';
import '../widgets/account_gate.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';

/// Прямой эфир: пока устаз не в эфире — заставка с автообновлением,
/// во время эфира — HLS-плеер.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  LiveStatus _status = LiveStatus.off;
  bool _checking = true;
  DateTime? _lastCheck;
  Timer? _poll;
  Timer? _watchdog;
  VideoPlayerController? _player;
  Duration _lastPos = Duration.zero;
  int _stallTicks = 0;
  bool _reopening = false;

  @override
  void initState() {
    super.initState();
    _check();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _check());
    // Сторож зависаний: если эфир «встал», вытаскиваем к живому краю.
    _watchdog =
        Timer.periodic(const Duration(seconds: 2), (_) => _watch());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _watchdog?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _watch() {
    final p = _player;
    if (!_status.live || p == null || !p.value.isInitialized || _reopening) {
      _stallTicks = 0;
      return;
    }
    final pos = p.value.position;
    final frozen = pos == _lastPos;
    _lastPos = pos;
    if (!frozen) {
      _stallTicks = 0;
      return;
    }
    _stallTicks++;
    if (_stallTicks == 2) {
      p.play(); // лёгкий толчок — вдруг просто спаузился на буферизации
    } else if (_stallTicks >= 4) {
      // ~8 секунд заморозки — переоткрываем поток к живому краю.
      _stallTicks = 0;
      _reopen();
    }
  }

  Future<void> _reopen() async {
    final url = _status.url;
    if (url.isEmpty || _reopening) return;
    _reopening = true;
    final old = _player;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await c.initialize();
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _player = c);
      await old?.dispose();
    } catch (e) {
      debugPrint('live reopen error: $e');
      await c.dispose();
    } finally {
      _lastPos = Duration.zero;
      _reopening = false;
    }
  }

  Future<void> _check() async {
    final s = await LiveService.fetch();
    if (!mounted) return;

    if (s.live && (_player == null || _status.url != s.url)) {
      await _player?.dispose();
      final c = VideoPlayerController.networkUrl(Uri.parse(s.url));
      _player = c;
      try {
        await c.initialize();
        await c.play();
      } catch (e) {
        // Поток ещё не готов — попробуем на следующем опросе.
        debugPrint('live init error: $e');
        await c.dispose();
        _player = null;
      }
    } else if (!s.live && _player != null) {
      await _player!.dispose();
      _player = null;
    }

    if (!mounted) return;
    setState(() {
      _status = s;
      _checking = false;
      _lastCheck = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(t('Прямой эфир')),
        centerTitle: true,
      ),
      body: DomeBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 66, 20, 20),
            child: _status.live
                ? _LiveView(status: _status, player: _player)
                : _OffAir(
                    checking: _checking,
                    lastCheck: _lastCheck,
                    onRefresh: () {
                      setState(() => _checking = true);
                      _check();
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// Заставка «эфира нет».
class _OffAir extends StatelessWidget {
  final bool checking;
  final DateTime? lastCheck;
  final VoidCallback onRefresh;
  const _OffAir(
      {required this.checking,
      required this.lastCheck,
      required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeSlideIn(
        child: GlassCard(
          radius: 26,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.3),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Icon(Icons.videocam_off_outlined,
                        size: 42,
                        color: Colors.white.withValues(alpha: 0.7)),
                  ),
                  if (checking)
                    const SizedBox(
                      width: 96,
                      height: 96,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.gold),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(t('Сейчас эфира нет'),
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                t('Когда устаз начнёт трансляцию, она автоматически появится здесь. Экран проверяет эфир каждые 15 секунд.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.7)),
              ),
              if (lastCheck != null) ...[
                const SizedBox(height: 10),
                Text(
                  '${t('Проверено в ')}'
                  '${lastCheck!.hour.toString().padLeft(2, '0')}:'
                  '${lastCheck!.minute.toString().padLeft(2, '0')}:'
                  '${lastCheck!.second.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.45)),
                ),
              ],
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: checking ? null : onRefresh,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.gold),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22)),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(t('Проверить сейчас')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плеер во время эфира (player может быть null, пока поток подключается —
/// комментарии доступны в любом случае).
class _LiveView extends StatefulWidget {
  final LiveStatus status;
  final VideoPlayerController? player;
  const _LiveView({required this.status, required this.player});

  @override
  State<_LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends State<_LiveView> {
  final _commentCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<LiveComment> _comments = [];
  Timer? _poll;
  String _name = t('Гость');
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadComments();
    _poll = Timer.periodic(
        const Duration(seconds: 4), (_) => _loadComments());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadName() async {
    final auth = await AuthService.create();
    if (!mounted) return;
    final n = auth.current?.name;
    if (n != null && n.trim().isNotEmpty) {
      setState(() => _name = n.trim());
    }
  }

  Future<void> _loadComments() async {
    final list = await CommentService.fetch();
    await ChatModeration.instance.init();
    if (!mounted) return;
    final atBottom = !_scrollCtrl.hasClients ||
        _scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 40;
    setState(() => _comments = ChatModeration.instance.filter(list));
    if (atBottom) _jumpToBottom();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await CommentService.post(_name, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _commentCtrl.clear();
      await _loadComments();
      _jumpToBottom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('Не удалось отправить комментарий'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _videoCard(context),
        const SizedBox(height: 14),
        Expanded(
          child: FadeSlideIn(
            delay: const Duration(milliseconds: 150),
            child: GlassCard(
              radius: 20,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline,
                          size: 18, color: AppColors.gold),
                      const SizedBox(width: 8),
                      Text(t('Комментарии'),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('${_comments.length}',
                          style: TextStyle(
                              fontSize: 13,
                              color:
                                  Colors.white.withValues(alpha: 0.5))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _commentsList()),
                  const SizedBox(height: 8),
                  _inputRow(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Видео эфира с ограниченной высотой (чтобы комментарии всегда были
  /// видны). Пока поток не готов — заставка «Подключение…».
  Widget _videoCard(BuildContext context) {
    final p = widget.player;
    final ready = p != null && p.value.isInitialized;
    // От доступной высоты (минус клавиатура), чтобы при вводе комментария
    // видео сжималось и лента с полем ввода всегда помещались.
    final mq = MediaQuery.of(context);
    final cap = (mq.size.height - mq.viewInsets.bottom) * 0.4;
    return FadeSlideIn(
      child: GlassCard(
        radius: 20,
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ready
                  ? LayoutBuilder(builder: (ctx, cons) {
                      final ratio = p.value.aspectRatio == 0
                          ? 16 / 9
                          : p.value.aspectRatio;
                      final h = math.min(cons.maxWidth / ratio, cap);
                      // Эфир только для просмотра — без паузы.
                      return SizedBox(
                        height: h,
                        width: double.infinity,
                        child: Stack(
                          alignment: Alignment.center,
                          fit: StackFit.expand,
                          children: [
                            FittedBox(
                              fit: BoxFit.contain,
                              child: SizedBox(
                                width: ratio * 1000,
                                height: 1000,
                                child: VideoPlayer(p),
                              ),
                            ),
                            const Positioned(
                                top: 10, left: 10, child: _LiveTag()),
                          ],
                        ),
                      );
                    })
                  : SizedBox(
                      height: cap * 0.55,
                      width: double.infinity,
                      child: Container(
                        color: Colors.black38,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                                color: AppColors.gold, strokeWidth: 2),
                            const SizedBox(height: 14),
                            Text(t('Подключение к эфиру…'),
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white
                                        .withValues(alpha: 0.8))),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(widget.status.title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                if (ready)
                  Icon(Icons.volume_up,
                      size: 20,
                      color: Colors.white.withValues(alpha: 0.7)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _commentsList() {
    if (_comments.isEmpty) {
      return Center(
        child: Text(
          t('Пока нет комментариев.\nНапишите первым!'),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.5)),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: EdgeInsets.zero,
      itemCount: _comments.length,
      itemBuilder: (_, i) {
        final c = _comments[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          // Долгое нажатие — пожаловаться или скрыть автора. Своё сообщение
          // трогать незачем, поэтому меню на нём не открываем.
          child: GestureDetector(
            onLongPress: c.name == _name ? null : () => _moderationSheet(c),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 14, height: 1.35),
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
          ),
        );
      },
    );
  }

  /// Меню жалобы и блокировки. Требование App Store к чатам: пожаловаться
  /// и заблокировать автора можно прямо из ленты.
  Future<void> _moderationSheet(LiveComment c) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.skyBottom,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('${c.name}: ${c.text}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.6))),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orange),
              title: Text(t('Пожаловаться')),
              subtitle: Text(t('Администратор проверит сообщение')),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.block, color: Colors.redAccent),
              title: Text(t('Скрыть этого пользователя')),
              subtitle: Text(t('Вы больше не увидите его сообщений')),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.white70),
              title: Text(t('Отмена')),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (action == 'block') {
      await ChatModeration.instance.block(c.name);
      if (!mounted) return;
      setState(() => _comments = ChatModeration.instance.filter(_comments));
      messenger.showSnackBar(SnackBar(
          content: Text(t('Сообщения этого пользователя скрыты'))));
      return;
    }
    final ok = await ChatModeration.instance
        .report(c, 'нарушение в чате эфира', by: _name);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
        content: Text(ok
            ? t('Жалоба отправлена администратору')
            : t('Не удалось отправить жалобу — проверьте связь'))));
  }

  /// Поле ввода — только вошедшим.
  ///
  /// Смотреть эфир может кто угодно: это обычное видео, аккаунт для него не
  /// нужен. А писать — нет: сообщение уходит под именем из профиля, по этому
  /// же имени работают жалоба и «скрыть автора». У гостей имя было бы одно на
  /// всех («Гость»), и блокировка одного грубияна прятала бы всех сразу.
  Widget _inputRow() {
    if (!AccountGate.isOpen(context)) return _signInToWriteRow();
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _commentCtrl,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            minLines: 1,
            maxLines: 3,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: appLang == Lang.ky ? '«$_name» атынан пикир…' : 'Комментарий от «$_name»…',
              hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45)),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.3),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: AppColors.gold),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: AppColors.accentGreen,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _sending ? null : _send,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, size: 20, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _signInToWriteRow() {
    return Row(
      children: [
        Icon(Icons.lock_outline,
            size: 18, color: Colors.white.withValues(alpha: 0.5)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            t('Комментарии — для зарегистрированных'),
            style: TextStyle(
                fontSize: 13.5,
                color: Colors.white.withValues(alpha: 0.7)),
          ),
        ),
        TextButton(
          onPressed: () => AccountGate.invite(context, t('Чат эфира')),
          child: Text(t('Войти'),
              style: const TextStyle(
                  color: AppColors.gold, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// Красный значок «LIVE» поверх видео.
class _LiveTag extends StatelessWidget {
  const _LiveTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulsingDot(color: Colors.white, size: 7),
          SizedBox(width: 6),
          Text('LIVE',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
        ],
      ),
    );
  }
}
