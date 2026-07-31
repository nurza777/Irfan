import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/access_service.dart';
import '../services/courses_service.dart';
import '../services/date_fmt.dart';
import '../services/lang.dart';
import '../services/watch_progress.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import 'lesson_player_screen.dart';

/// Уроки выбранного устаза: направления → курсы → уроки.
/// Видео играют внутри приложения, сторонние ссылки открываются в браузере.
class TeacherCoursesPage extends StatelessWidget {
  final String teacherName;
  final String teacherBio;
  final TeacherCourses? courses;

  const TeacherCoursesPage({
    super.key,
    required this.teacherName,
    required this.teacherBio,
    required this.courses,
  });

  @override
  Widget build(BuildContext context) {
    final directions = courses?.directions ?? const <RemoteDirection>[];
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(teacherName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18)),
        centerTitle: true,
      ),
      body: DomeBackground(
        child: directions.isEmpty
            ? Center(
                child: FadeSlideIn(
                  child: GlassCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.school_outlined,
                            size: 40,
                            color: Colors.white.withValues(alpha: 0.7)),
                        const SizedBox(height: 12),
                        Text(
                            t('Уроков пока нет.\nУстаз скоро опубликует первые.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 15,
                                height: 1.4,
                                color:
                                    Colors.white.withValues(alpha: 0.8))),
                      ],
                    ),
                  ),
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                    16, MediaQuery.of(context).padding.top + 72, 16, 16),
                children: [
                  if (teacherBio.isNotEmpty)
                    FadeSlideIn(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          radius: 16,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.verified_outlined,
                                  color: AppColors.gold, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(teacherBio,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  for (final (di, d) in directions.indexed) ...[
                    FadeSlideIn(
                      delay: Duration(milliseconds: 80 * di),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.category_outlined,
                                size: 18, color: AppColors.goldLight),
                            const SizedBox(width: 8),
                            Text(d.title,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
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
                          course: c, direction: d.title, index: di + ci),
                  ],
                ],
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
      {required this.course, required this.direction, required this.index});

  @override
  State<_CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<_CourseCard> {
  bool _open = false;

  Future<void> _openLesson(RemoteLesson l) async {
    if (l.url.isEmpty) return;
    if (l.isDirectVideo) {
      // Плееру отдаём все видео курса — из него можно перейти к следующему
      // уроку. Ссылки на сторонние сайты в этот список не попадают: их
      // плеер проиграть не может.
      final playable =
          widget.course.lessons.where((e) => e.isDirectVideo).toList();
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => LessonPlayerScreen(
                    lessons: playable,
                    index: playable.indexOf(l),
                    courseTitle: widget.course.title,
                  )));
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
                          : '${c.subtitle.isEmpty ? '' : '${c.subtitle} · '}${c.lessons.length} ${t('урок(ов)')}',
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
                              color: Colors.white.withValues(alpha: 0.1)),
                          for (final (j, l) in c.lessons.indexed)
                            _LessonTile(
                                lesson: l,
                                number: j + 1,
                                onTap: () => _openLesson(l)),
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

/// Строка урока в каталоге: показывает, что уже просмотрено и где человек
/// остановился, — иначе в длинном курсе не найти, на чём прервался.
class _LessonTile extends StatelessWidget {
  final RemoteLesson lesson;
  final int number;
  final VoidCallback onTap;

  const _LessonTile(
      {required this.lesson, required this.number, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WatchProgress.instance,
      builder: (context, _) {
        final wp = WatchProgress.instance;
        final video = lesson.isDirectVideo;
        final done = video && wp.isDone(lesson.url);
        final frac = video ? wp.fraction(lesson.url) : 0.0;
        return ListTile(
          dense: true,
          leading: Icon(
            !video
                ? Icons.link
                : done
                    ? Icons.check_circle
                    : Icons.play_circle_outline,
            color: done ? AppColors.accentGreen : AppColors.goldLight,
            size: 22,
          ),
          title: Text('$number. ${lesson.title}',
              style: const TextStyle(fontSize: 14)),
          subtitle: done
              ? Text(t('Просмотрено'),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.accentGreen))
              : frac > 0
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6, right: 24),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: frac,
                          minHeight: 3,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.2),
                          valueColor:
                              const AlwaysStoppedAnimation(AppColors.gold),
                        ),
                      ),
                    )
                  : null,
          onTap: onTap,
        );
      },
    );
  }
}
