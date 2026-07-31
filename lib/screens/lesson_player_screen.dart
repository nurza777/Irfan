import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/courses_service.dart';
import '../services/lang.dart';
import '../services/watch_progress.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';

/// Плеер урока: пауза, перемотка, скорость, полный экран, продолжение с того
/// места, где остановились, и переход к следующему уроку курса.
class LessonPlayerScreen extends StatefulWidget {
  /// Все уроки курса — чтобы переключаться, не возвращаясь в каталог.
  final List<RemoteLesson> lessons;
  final int index;
  final String courseTitle;

  const LessonPlayerScreen({
    super.key,
    required this.lessons,
    required this.index,
    this.courseTitle = '',
  });

  @override
  State<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends State<LessonPlayerScreen>
    with WidgetsBindingObserver {
  static const _seekStep = Duration(seconds: 10);
  static const _hideAfter = Duration(seconds: 3);
  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  VideoPlayerController? _c;
  late int _index = widget.index;
  String? _error;
  bool _fullscreen = false;
  bool _controls = true;
  bool _dragging = false;
  Duration _dragPos = Duration.zero;
  double _speed = 1.0;
  Timer? _hideTimer;
  Duration _lastSaved = Duration.zero;
  bool _resumed = false;
  bool _awake = false;

  RemoteLesson get _lesson => widget.lessons[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    await WatchProgress.instance.init();
    await _open(_index);
  }

  Future<void> _open(int i) async {
    _saveProgress(force: true);
    final old = _c;
    _hideTimer?.cancel();
    setState(() {
      _index = i;
      _c = null;
      _error = null;
      _resumed = false;
      _controls = true;
      _lastSaved = Duration.zero;
    });
    await old?.dispose();

    final c = VideoPlayerController.networkUrl(
      Uri.parse(_lesson.url),
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
    );
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.setPlaybackSpeed(_speed);
      // Возврат к месту остановки — до первого кадра, чтобы урок не начинал
      // играть сначала и не сбивал человека.
      final resume = WatchProgress.instance.resumeAt(_lesson.url);
      if (resume > 0 && resume < c.value.duration.inSeconds) {
        await c.seekTo(Duration(seconds: resume));
        _resumed = true;
      }
      c.addListener(_onTick);
      setState(() => _c = c);
      await c.play();
      _restartHideTimer();
      if (_resumed && mounted) _showResumeHint();
    } catch (_) {
      await c.dispose();
      if (!mounted) return;
      setState(() => _error = _errorText());
    }
  }

  String _errorText() => appLang == Lang.ky
      ? 'Видео ачылган жок. Интернетти текшериңиз.'
      : 'Не удалось открыть видео. Проверьте интернет.';

  void _showResumeHint() {
    final at = _fmt(_c!.value.position);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Text('${t('Продолжаем с')} $at'),
      action: SnackBarAction(
        label: t('Сначала'),
        textColor: AppColors.goldLight,
        onPressed: () {
          _c?.seekTo(Duration.zero);
          WatchProgress.instance.reset(_lesson.url);
        },
      ),
    ));
  }

  /// Тик плеера: сюда приходит и позиция, и ошибка воспроизведения.
  void _onTick() {
    final v = _c?.value;
    if (v == null) return;
    if (v.hasError && _error == null) {
      setState(() => _error = _errorText());
      return;
    }
    _saveProgress();
    // Экран не гасим, пока идёт воспроизведение; на паузе человек читает
    // конспект или отошёл, держать подсветку незачем. Дёргаем только на
    // смене состояния — тик приходит по нескольку раз в секунду.
    if (v.isPlaying != _awake) {
      _awake = v.isPlaying;
      WakelockPlus.toggle(enable: _awake);
    }
    if (_ended(v) && !_controls) setState(() => _controls = true);
  }

  bool _ended(VideoPlayerValue v) =>
      v.duration > Duration.zero &&
      v.position >= v.duration - const Duration(milliseconds: 400) &&
      !v.isPlaying;

  void _saveProgress({bool force = false}) {
    final v = _c?.value;
    if (v == null || !v.isInitialized) return;
    // Раз в 5 секунд: запись в prefs дешёвая, но тик приходит по 5 раз в
    // секунду, и толкать диск так часто ни к чему.
    if (!force && (v.position - _lastSaved).abs() < const Duration(seconds: 5)) {
      return;
    }
    _lastSaved = v.position;
    WatchProgress.instance.save(_lesson.url, v.position, v.duration);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _c?.pause();
      _saveProgress(force: true);
      _awake = false;
      WakelockPlus.disable();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _saveProgress(force: true);
    _c?.removeListener(_onTick);
    _c?.dispose();
    WakelockPlus.disable();
    if (_fullscreen) _restoreOrientation();
    super.dispose();
  }

  // ── Управление ────────────────────────────────────────────────────────

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (_c?.value.isPlaying != true) return;
    _hideTimer = Timer(_hideAfter, () {
      if (mounted && !_dragging) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _restartHideTimer();
  }

  void _togglePlay() {
    final c = _c;
    if (c == null) return;
    if (_ended(c.value)) {
      c.seekTo(Duration.zero);
      c.play();
    } else {
      c.value.isPlaying ? c.pause() : c.play();
    }
    setState(() => _controls = true);
    _restartHideTimer();
  }

  void _seekBy(Duration d) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    var target = c.value.position + d;
    if (target < Duration.zero) target = Duration.zero;
    if (target > c.value.duration) target = c.value.duration;
    c.seekTo(target);
    setState(() => _controls = true);
    _restartHideTimer();
  }

  void _setSpeed(double s) {
    setState(() => _speed = s);
    _c?.setPlaybackSpeed(s);
    _restartHideTimer();
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      _restoreOrientation();
    }
    _restartHideTimer();
  }

  /// Возврат из полного экрана — строго в портрет и там остаёмся. Возвращать
  /// свободное вращение нельзя: телефон человек всё ещё держит боком, и экран
  /// тут же лёг бы обратно набок.
  void _restoreOrientation() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  bool get _hasNext => _index + 1 < widget.lessons.length;
  bool get _hasPrev => _index > 0;

  // ── Экран ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_fullscreen) {
      return PopScope(
        // Системный «назад» в полноэкранном режиме должен сворачивать плеер,
        // а не закрывать урок целиком.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toggleFullscreen();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: _videoArea(fullscreen: true),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_lesson.title,
            style: const TextStyle(fontSize: 17),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        centerTitle: true,
      ),
      body: DomeBackground(
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 44),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                // Вертикальное видео иначе занимает весь экран, и список
                // уроков под ним схлопывается в ничто.
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.45),
                  child: GlassCard(
                    radius: 18,
                    padding: const EdgeInsets.all(6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: _videoArea(fullscreen: false),
                    ),
                  ),
                ),
              ),
              Expanded(child: _lessonList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoArea({required bool fullscreen}) {
    final c = _c;
    Widget content;
    if (_error != null) {
      content = _errorBox();
    } else if (c == null || !c.value.isInitialized) {
      content = const Center(
          child: CircularProgressIndicator(color: AppColors.gold));
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
          _gestureLayer(c),
          // Перерисовывается только слой управления: позиция меняется по
          // нескольку раз в секунду, а фон и список уроков — нет.
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (_, v, __) => _controlsLayer(c, v, fullscreen),
          ),
        ],
      );
    }

    if (fullscreen) return content;
    return AspectRatio(
      aspectRatio: (c?.value.isInitialized ?? false) && c!.value.aspectRatio > 0
          ? c.value.aspectRatio
          : 16 / 9,
      child: Container(color: Colors.black, child: content),
    );
  }

  Widget _errorBox() => Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, color: AppColors.gold, size: 34),
                const SizedBox(height: 10),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => _open(_index),
                  icon: const Icon(Icons.refresh, color: AppColors.goldLight),
                  label: Text(t('Повторить'),
                      style: const TextStyle(color: AppColors.goldLight)),
                ),
              ],
            ),
          ),
        ),
      );

  /// Одиночный тап показывает/прячет управление, двойной по краю — перемотка
  /// на 10 секунд (привычный жест по видео).
  Widget _gestureLayer(VideoPlayerController c) => Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTap: () => _seekBy(-_seekStep),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTap: () => _seekBy(_seekStep),
            ),
          ),
        ],
      );

  Widget _controlsLayer(
      VideoPlayerController c, VideoPlayerValue v, bool fullscreen) {
    final show = _controls || _ended(v);
    return AnimatedOpacity(
      opacity: show ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !show,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.45),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.6),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
          // В полном экране вырез и «домашняя» полоса уезжают вбок —
          // без SafeArea кнопки попадают прямо под них.
          child: SafeArea(
            top: fullscreen,
            bottom: fullscreen,
            left: fullscreen,
            right: fullscreen,
            child: Column(
              children: [
                _topBar(fullscreen),
                Expanded(child: Center(child: _centerButtons(c, v))),
                _bottomBar(c, v, fullscreen),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(bool fullscreen) => Padding(
        padding: EdgeInsets.fromLTRB(fullscreen ? 12 : 4, fullscreen ? 8 : 2, 4, 0),
        child: Row(
          children: [
            if (fullscreen)
              IconButton(
                onPressed: _toggleFullscreen,
                icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                tooltip: t('Свернуть'),
              ),
            if (fullscreen)
              Expanded(
                child: Text(_lesson.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              )
            else
              const Spacer(),
            PopupMenuButton<double>(
              tooltip: t('Скорость'),
              color: AppColors.skyBottom,
              initialValue: _speed,
              onSelected: _setSpeed,
              itemBuilder: (_) => [
                for (final s in _speeds)
                  PopupMenuItem(
                    value: s,
                    child: Row(
                      children: [
                        Icon(
                            s == _speed
                                ? Icons.check
                                : Icons.check_box_outline_blank,
                            size: 16,
                            color: s == _speed
                                ? AppColors.goldLight
                                : Colors.transparent),
                        const SizedBox(width: 8),
                        Text(s == 1.0 ? '1× (${t('обычная')})' : '$s×'),
                      ],
                    ),
                  ),
              ],
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${_speed == 1.0 ? '1' : _speed}×',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      );

  Widget _centerButtons(VideoPlayerController c, VideoPlayerValue v) {
    if (v.isBuffering && !_ended(v)) {
      return const SizedBox(
        width: 46,
        height: 46,
        child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 3),
      );
    }
    final ended = _ended(v);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _round(Icons.replay_10, 26, () => _seekBy(-_seekStep)),
        const SizedBox(width: 22),
        _round(
          ended
              ? Icons.replay
              : (v.isPlaying ? Icons.pause : Icons.play_arrow),
          40,
          _togglePlay,
          big: true,
        ),
        const SizedBox(width: 22),
        _round(Icons.forward_10, 26, () => _seekBy(_seekStep)),
      ],
    );
  }

  Widget _round(IconData icon, double size, VoidCallback onTap,
          {bool big = false}) =>
      Material(
        color: Colors.black.withValues(alpha: big ? 0.45 : 0.3),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(big ? 12 : 8),
            child: Icon(icon, size: size, color: Colors.white),
          ),
        ),
      );

  Widget _bottomBar(
      VideoPlayerController c, VideoPlayerValue v, bool fullscreen) {
    final pos = _dragging ? _dragPos : v.position;
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, fullscreen ? 14 : 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProgressBar(
            position: pos,
            duration: v.duration,
            buffered: v.buffered.isEmpty ? Duration.zero : v.buffered.last.end,
            onDragStart: () {
              _hideTimer?.cancel();
              setState(() {
                _dragging = true;
                _dragPos = v.position;
              });
            },
            onDrag: (d) => setState(() => _dragPos = d),
            onDragEnd: (d) {
              c.seekTo(d);
              setState(() => _dragging = false);
              _restartHideTimer();
            },
          ),
          Row(
            children: [
              Text('${_fmt(pos)} / ${_fmt(v.duration)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.9),
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const Spacer(),
              if (_hasPrev)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _open(_index - 1),
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                  tooltip: t('Предыдущий урок'),
                ),
              if (_hasNext)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _open(_index + 1),
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                  tooltip: t('Следующий урок'),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _toggleFullscreen,
                icon: Icon(
                    fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white),
                tooltip: fullscreen ? t('Свернуть') : t('Во весь экран'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Под плеером — остальные уроки курса: досмотрев один, человек обычно
  /// переходит к следующему, и возвращаться в каталог ради этого незачем.
  Widget _lessonList() {
    return ListenableBuilder(
      listenable: WatchProgress.instance,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          if (widget.courseTitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.school_outlined,
                      size: 16, color: AppColors.goldLight),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(widget.courseTitle,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  Text('${_index + 1} / ${widget.lessons.length}',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.6))),
                ],
              ),
            ),
          for (final (i, l) in widget.lessons.indexed)
            _LessonRow(
              lesson: l,
              number: i + 1,
              current: i == _index,
              onTap: i == _index ? null : () => _open(i),
            ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    if (d.inSeconds <= 0) return '0:00';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }
}

/// Полоска перемотки: загруженное показываем отдельным слоем, иначе
/// непонятно, докуда видео уже дотянулось, и перемотка выглядит как зависание.
class _ProgressBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final VoidCallback onDragStart;
  final ValueChanged<Duration> onDrag;
  final ValueChanged<Duration> onDragEnd;

  const _ProgressBar({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
  });

  Duration _at(double dx, double width) {
    final f = (dx / width).clamp(0.0, 1.0);
    return Duration(milliseconds: (duration.inMilliseconds * f).round());
  }

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        double frac(Duration d) =>
            total <= 0 ? 0 : (d.inMilliseconds / total).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (e) {
            onDragStart();
            onDragEnd(_at(e.localPosition.dx, w));
          },
          onHorizontalDragStart: (_) => onDragStart(),
          onHorizontalDragUpdate: (e) => onDrag(_at(e.localPosition.dx, w)),
          onHorizontalDragEnd: (_) => onDragEnd(position),
          child: SizedBox(
            height: 26,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: frac(buffered),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: frac(position),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment(frac(position) * 2 - 1, 0),
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: AppColors.goldLight,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LessonRow extends StatelessWidget {
  final RemoteLesson lesson;
  final int number;
  final bool current;
  final VoidCallback? onTap;

  const _LessonRow({
    required this.lesson,
    required this.number,
    required this.current,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final wp = WatchProgress.instance;
    final done = wp.isDone(lesson.url);
    final frac = wp.fraction(lesson.url);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        radius: 14,
        padding: EdgeInsets.zero,
        child: ListTile(
          dense: true,
          selected: current,
          selectedTileColor: AppColors.gold.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: Icon(
            current
                ? Icons.play_circle_fill
                : done
                    ? Icons.check_circle
                    : Icons.play_circle_outline,
            color: done && !current ? AppColors.accentGreen : AppColors.goldLight,
          ),
          title: Text('$number. ${lesson.title}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: current ? FontWeight.w700 : FontWeight.w400)),
          subtitle: frac > 0 && !done
              ? Padding(
                  padding: const EdgeInsets.only(top: 5, right: 30),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.gold),
                    ),
                  ),
                )
              : done
                  ? Text(t('Просмотрено'),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.accentGreen))
                  : null,
          onTap: onTap,
        ),
      ),
    );
  }
}
