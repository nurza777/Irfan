import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../services/courses_service.dart';
import '../services/access_service.dart';
import '../services/date_fmt.dart';
import '../services/lang.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';

/// Курсы устаза: каталог загружается с сервера (публикует приложение
/// «Ирфан Устаз»); уроки-видео играют внутри, ссылки открываются в браузере.
class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  Catalog? _catalog;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cat = await CoursesService.fetch();
    if (!mounted) return;
    setState(() {
      _catalog = cat;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(t('Курсы')),
        centerTitle: true,
        actions: [
          IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh, color: AppColors.gold)),
        ],
      ),
      body: DomeBackground(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold))
            : _catalog == null
                ? _message(
                    t('Сервер курсов недоступен.\nПроверьте интернет и обновите.'))
                : _catalog!.directions.isEmpty
                    ? _message(
                        t('Курсов пока нет.\nУстаз скоро опубликует первые уроки.'))
                    : ListView(
                        padding: EdgeInsets.fromLTRB(16,
                            MediaQuery.of(context).padding.top + 72, 16, 16),
                        children: [
                          if (_catalog!.author.isNotEmpty)
                            FadeSlideIn(
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 12),
                                child: GlassCard(
                                  radius: 16,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.verified_outlined,
                                          color: AppColors.gold,
                                          size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          appLang == Lang.ky
              ? 'Курстарды жүктөгөн: ${_catalog!.author}'
              : 'Курсы загрузил: ${_catalog!.author}',
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight:
                                                  FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          for (final (di, d)
                              in _catalog!.directions.indexed) ...[
                            FadeSlideIn(
                              delay: Duration(milliseconds: 80 * di),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    4, 6, 4, 8),
                                child: Row(
                                  children: [
                                    const Icon(Icons.category_outlined,
                                        size: 18,
                                        color: AppColors.goldLight),
                                    const SizedBox(width: 8),
                                    Text(d.title,
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight:
                                                FontWeight.w700)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Container(
                                          height: 1,
                                          color: AppColors.gold
                                              .withValues(alpha: 0.35)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            for (final (ci, c) in d.courses.indexed)
                              _CourseCard(
                                  course: c,
                                  direction: d.title,
                                  index: di + ci),
                          ],
                        ],
                      ),
      ),
    );
  }

  Widget _message(String text) {
    return Center(
      child: FadeSlideIn(
        child: GlassCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined,
                  size: 40, color: Colors.white.withValues(alpha: 0.7)),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: Colors.white.withValues(alpha: 0.8))),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseCard extends StatefulWidget {
  final RemoteCourse course;
  final String direction;
  final int index;
  const _CourseCard(
      {required this.course,
      required this.direction,
      required this.index});

  @override
  State<_CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<_CourseCard> {
  bool _open = false;

  Future<void> _openLesson(RemoteLesson l) async {
    if (l.url.isEmpty) return;
    if (l.isDirectVideo) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => LessonPlayerScreen(lesson: l)));
    } else if (l.isSafeLink) {
      // Только http/https — ссылка приходит с сервера, не запускаем
      // произвольные схемы (tel:, deep links и т.п.).
      await launchUrl(Uri.parse(l.url),
          mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('Ссылка урока имеет недопустимый формат'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    // Доступы приходят с сервера уже после первого кадра, поэтому карточка
    // подписана на AccessService — иначе замок бы не появился.
    return ListenableBuilder(
      listenable: AccessService.instance,
      builder: (context, _) => _card(context, c),
    );
  }

  Widget _card(BuildContext context, RemoteCourse c) {
    final access = AccessService.instance;
    final open = access.canOpenCourse(widget.direction, c.title);
    final until = open ? access.courseUntil(widget.direction, c.title) : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FadeSlideIn(
        delay: Duration(milliseconds: 90 * widget.index),
        child: GlassCard(
          radius: 16,
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.domeGreen.withValues(alpha: 0.5),
                    border: Border.all(color: AppColors.gold, width: 1),
                  ),
                  child: Icon(open ? Icons.menu_book : Icons.lock_outline,
                      color: AppColors.cream, size: 22),
                ),
                title: Text(c.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  !open
                      ? t('Доступ закрыт — обратитесь к устазу')
                      : until != null
                          ? '${t('Доступ до')} ${fmtDateShort(until)}'
                          : '${c.subtitle.isEmpty ? '' : '${c.subtitle} · '}${c.lessons.length} ${appLang == Lang.ky ? 'сабак' : 'урок(ов)'}',
                  style: TextStyle(
                      fontSize: 13,
                      color: open
                          ? Colors.white.withValues(alpha: 0.65)
                          : Colors.orangeAccent.withValues(alpha: 0.9)),
                ),
                trailing: AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(Icons.keyboard_arrow_down,
                      color: AppColors.gold),
                ),
                onTap: open
                    ? () => setState(() => _open = !_open)
                    : () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                t('Доступ к этому курсу пока не открыт')))),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: !_open || !open
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          Divider(
                              height: 1,
                              color:
                                  Colors.white.withValues(alpha: 0.1)),
                          for (final (j, l) in c.lessons.indexed)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                l.isDirectVideo
                                    ? Icons.play_circle_outline
                                    : Icons.link,
                                color: AppColors.goldLight,
                                size: 22,
                              ),
                              title: Text('${j + 1}. ${l.title}',
                                  style:
                                      const TextStyle(fontSize: 14)),
                              onTap: () => _openLesson(l),
                            ),
                          if (c.lessons.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(t('Уроки скоро появятся'),
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white
                                          .withValues(alpha: 0.6))),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плеер урока (mp4/HLS).
class LessonPlayerScreen extends StatefulWidget {
  final RemoteLesson lesson;
  const LessonPlayerScreen({super.key, required this.lesson});

  @override
  State<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends State<LessonPlayerScreen> {
  late final VideoPlayerController _c =
      VideoPlayerController.networkUrl(Uri.parse(widget.lesson.url));
  String? _error;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) {
        setState(() {});
        _c.play();
      }
    }).catchError((e) {
      if (mounted) setState(() => _error = appLang == Lang.ky ? 'Видео ачылган жок: $e' : 'Не удалось открыть видео: $e');
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.lesson.title,
            style: const TextStyle(fontSize: 17)),
        centerTitle: true,
      ),
      body: DomeBackground(
        child: Center(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14)),
                )
              : !_c.value.isInitialized
                  ? const CircularProgressIndicator(
                      color: AppColors.gold)
                  : Padding(
                      padding: const EdgeInsets.all(14),
                      child: GlassCard(
                        radius: 18,
                        padding: const EdgeInsets.all(8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: _c.value.aspectRatio,
                            child: GestureDetector(
                              onTap: () => setState(() =>
                                  _c.value.isPlaying
                                      ? _c.pause()
                                      : _c.play()),
                              child: Stack(
                                alignment: Alignment.center,
                                fit: StackFit.expand,
                                children: [
                                  VideoPlayer(_c),
                                  if (!_c.value.isPlaying)
                                    Container(
                                      color: Colors.black38,
                                      child: const Icon(
                                          Icons.play_arrow,
                                          size: 64,
                                          color: Colors.white),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
        ),
      ),
    );
  }
}
