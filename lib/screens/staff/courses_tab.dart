import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/lang.dart';
import '../../services/staff_api.dart';
import '../../widgets/dome_background.dart';
import '../../widgets/glass.dart';
import '../../services/staff_auth.dart';
import '../../theme.dart';

/// Курсы устаза: направления → курсы → уроки. Публикация на сервер
/// идёт от имени вошедшего устаза.
class CoursesTab extends StatefulWidget {
  const CoursesTab({super.key});

  @override
  State<CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends State<CoursesTab> {
  List<Direction> _directions = [];
  PendingCourses? _pending;
  bool _loading = true;
  bool _publishing = false;
  bool _dirty = false;

  StaffApi get _api => const StaffApi();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _api.fetchDirections();
      final pending = await _api.fetchPendingCourses();
      if (!mounted) return;
      setState(() {
        _directions = list;
        _pending = pending;
        _loading = false;
        _dirty = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Не удалось загрузить каталог с сервера');
    }
  }

  Future<void> _publish() async {
    final author = StaffAuth.instance.session?.name ?? 'Устаз';
    setState(() => _publishing = true);
    // Ученикам публикует только админ (в веб-панели) — отсюда уходит заявка.
    final err = await _api.submitDirections(_directions, author);
    if (!mounted) return;
    setState(() => _publishing = false);
    if (err == null) {
      setState(() => _dirty = false);
      _snack('Отправлено администратору на модерацию');
      _load(); // обновить статус заявки
    } else {
      _snack(err);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Future<void> _directionDialog([Direction? d]) async {
    final ctrl = TextEditingController(text: d?.title ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.skyBottom,
        title: Text(d == null ? 'Новое направление' : 'Переименовать'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Название (например, Фикх)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить')),
        ],
      ),
    );
    final title = ctrl.text.trim();
    ctrl.dispose();
    if (!mounted || ok != true || title.isEmpty) return;
    setState(() {
      if (d == null) {
        _directions.add(Direction(title: title));
      } else {
        d.title = title;
      }
      _dirty = true;
    });
  }

  Future<void> _openDirection(Direction d) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DirectionScreen(direction: d)),
    );
    setState(() => _dirty = true);
  }

  @override
  Widget build(BuildContext context) {
    final author = StaffAuth.instance.session?.name ?? 'Устаз';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Направления',
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w700)),
                    Text('Публикуются от имени: $author',
                        style: TextStyle(
                            fontSize: 13,
                            color:
                                Colors.white.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              PressableScale(
                onTap: _load,
                child: const GlassCard(
                  radius: 20,
                  blur: 10,
                  darkness: 0.18,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.refresh,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PressableScale(
                onTap: () => _directionDialog(),
                child: const GlassCard(
                  radius: 20,
                  blur: 10,
                  darkness: 0.18,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child:
                        Icon(Icons.add, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_pending != null) _ModerationBanner(pending: _pending!),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.gold))
                : _directions.isEmpty
                    ? Center(
                        child: GlassCard(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                  'Создайте направления,\nвнутри — курсы с уроками',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 15)),
                              const SizedBox(height: 12),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor:
                                        AppColors.accentGreen),
                                onPressed: () => _directionDialog(),
                                child: const Text(
                                    'Создать направление'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _directions.length,
                        itemBuilder: (context, i) {
                          final d = _directions[i];
                          final lessons = d.courses.fold<int>(
                              0, (s, c) => s + c.lessons.length);
                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: 10),
                            child: FadeSlideIn(
                              delay:
                                  Duration(milliseconds: 60 * i),
                              child: PressableScale(
                                onTap: () => _openDirection(d),
                                child: GlassCard(
                                  radius: 16,
                                  padding:
                                      const EdgeInsets.fromLTRB(
                                          14, 12, 6, 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.domeGreen
                                              .withValues(
                                                  alpha: 0.5),
                                          border: Border.all(
                                              color:
                                                  AppColors.gold,
                                              width: 1),
                                        ),
                                        child: const Icon(
                                            Icons.category_outlined,
                                            color: AppColors.cream,
                                            size: 22),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                          children: [
                                            Text(d.title,
                                                style:
                                                    const TextStyle(
                                                        fontSize:
                                                            16,
                                                        fontWeight:
                                                            FontWeight
                                                                .w600)),
                                            Text(
                                              '${plural(d.courses.length, 'курс', 'курса', 'курсов')}'
                                              ' · '
                                              '${plural(lessons, 'урок', 'урока', 'уроков')}',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors
                                                      .white
                                                      .withValues(
                                                          alpha:
                                                              0.65)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            _directionDialog(d),
                                        icon: const Icon(
                                            Icons.edit_outlined,
                                            color: AppColors.gold,
                                            size: 20),
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            setState(() {
                                          _directions.removeAt(i);
                                          _dirty = true;
                                        }),
                                        icon: Icon(
                                            Icons.delete_outline,
                                            color: Colors.redAccent
                                                .withValues(
                                                    alpha: 0.8),
                                            size: 20),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor:
                    _dirty ? AppColors.accentGreen : AppColors.domeDark,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: _publishing ? null : _publish,
              icon: _publishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_outlined, size: 20),
              label: const Text(
                'Отправить на модерацию',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Баннер статуса заявки на модерацию (виден устазу).
class _ModerationBanner extends StatelessWidget {
  final PendingCourses pending;
  const _ModerationBanner({required this.pending});

  @override
  Widget build(BuildContext context) {
    final (color, icon, text) = switch (pending.status) {
      ModerationStatus.pending => (
          AppColors.gold,
          Icons.hourglass_top,
          'Отправлено на модерацию — ждёт решения администратора'
        ),
      ModerationStatus.approved => (
          AppColors.accentGreen,
          Icons.check_circle,
          'Одобрено и опубликовано студентам'
        ),
      ModerationStatus.rejected => (
          Colors.redAccent,
          Icons.cancel,
          pending.reason.isEmpty
              ? 'Отклонено администратором'
              : 'Отклонено: ${pending.reason}'
        ),
      ModerationStatus.none => (Colors.transparent, Icons.info, ''),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, height: 1.3))),
        ],
      ),
    );
  }
}

/// Курсы внутри направления.
class DirectionScreen extends StatefulWidget {
  final Direction direction;
  const DirectionScreen({super.key, required this.direction});

  @override
  State<DirectionScreen> createState() => _DirectionScreenState();
}

class _DirectionScreenState extends State<DirectionScreen> {
  Future<void> _editCourse([Course? course]) async {
    final edited = await Navigator.push<Course>(
      context,
      MaterialPageRoute(
          builder: (_) => CourseEditScreen(course: course)),
    );
    if (edited == null) return;
    setState(() {
      if (course == null) widget.direction.courses.add(edited);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.direction;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(d.title),
        centerTitle: true,
        actions: [
          IconButton(
              onPressed: () => _editCourse(),
              icon: const Icon(Icons.add, color: AppColors.gold)),
        ],
      ),
      body: DomeBackground(
        child: d.courses.isEmpty
            ? Center(
                child: GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('В направлении «${d.title}» пока нет курсов',
                          style: const TextStyle(fontSize: 15)),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentGreen),
                        onPressed: () => _editCourse(),
                        child: const Text('Добавить курс'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: EdgeInsets.fromLTRB(
                    20, MediaQuery.of(context).padding.top + 66, 20, 20),
                itemCount: d.courses.length,
                itemBuilder: (context, i) {
                  final c = d.courses[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: 60 * i),
                      child: GlassCard(
                        radius: 16,
                        padding:
                            const EdgeInsets.fromLTRB(14, 10, 6, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(c.title,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight:
                                              FontWeight.w600)),
                                  Text(
                                    '${c.subtitle.isEmpty ? '' : '${c.subtitle} · '}'
                                    '${plural(c.lessons.length, 'урок', 'урока', 'уроков')}',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white
                                            .withValues(alpha: 0.65)),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _editCourse(c),
                              icon: const Icon(Icons.edit_outlined,
                                  color: AppColors.gold, size: 22),
                            ),
                            IconButton(
                              onPressed: () => setState(
                                  () => d.courses.removeAt(i)),
                              icon: Icon(Icons.delete_outline,
                                  color: Colors.redAccent
                                      .withValues(alpha: 0.8),
                                  size: 22),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Редактор курса: название, описание, уроки (ссылка или загрузка видео).
class CourseEditScreen extends StatefulWidget {
  final Course? course;
  const CourseEditScreen({super.key, this.course});

  @override
  State<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends State<CourseEditScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.course?.title ?? '');
  late final TextEditingController _subtitle =
      TextEditingController(text: widget.course?.subtitle ?? '');
  late final List<Lesson> _lessons =
      List.of(widget.course?.lessons ?? const <Lesson>[]);
  bool _uploading = false;

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Future<void> _addLessonDialog() async {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.skyBottom,
        title: const Text('Новый урок'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration:
                  const InputDecoration(labelText: 'Название урока'),
            ),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                  labelText: 'Ссылка на видео (YouTube/mp4)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Добавить')),
        ],
      ),
    );
    final title = titleCtrl.text.trim();
    final url = urlCtrl.text.trim();
    titleCtrl.dispose();
    urlCtrl.dispose();
    if (!mounted || added != true || title.isEmpty) return;
    setState(() => _lessons.add(Lesson(title: title, url: url)));
  }

  Future<void> _uploadVideoLesson() async {
    final picked =
        await FilePicker.pickFiles(type: FileType.video, withData: false);
    final path = picked?.files.single.path;
    if (path == null) return;
    setState(() => _uploading = true);
    final (url, err) =
        await const StaffApi().uploadVideo(File(path));
    if (!mounted) return;
    setState(() => _uploading = false);
    if (err != null) {
      _snack(err);
      return;
    }
    final name = picked!.files.single.name;
    setState(() => _lessons.add(Lesson(title: name, url: url!)));
    _snack('Видео загружено на сервер');
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      _snack('Введите название курса');
      return;
    }
    final c = widget.course ?? Course(title: '');
    c.title = _title.text.trim();
    c.subtitle = _subtitle.text.trim();
    c.lessons
      ..clear()
      ..addAll(_lessons);
    Navigator.pop(context, c);
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
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
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.course == null
            ? 'Новый курс'
            : 'Редактирование курса'),
        centerTitle: true,
        actions: [
          IconButton(
              onPressed: _save,
              icon: const Icon(Icons.check, color: AppColors.gold)),
        ],
      ),
      body: DomeBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 66, 20, 20),
            children: [
              TextField(
                  controller: _title, decoration: _dec('Название курса')),
              const SizedBox(height: 12),
              TextField(
                  controller: _subtitle,
                  decoration: _dec('Короткое описание')),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text('Уроки',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addLessonDialog,
                    icon: const Icon(Icons.link,
                        size: 18, color: AppColors.gold),
                    label: const Text('Ссылка',
                        style: TextStyle(color: AppColors.cream)),
                  ),
                  TextButton.icon(
                    onPressed: _uploading ? null : _uploadVideoLesson,
                    icon: _uploading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.gold))
                        : const Icon(Icons.upload_file,
                            size: 18, color: AppColors.gold),
                    label: const Text('Видео',
                        style: TextStyle(color: AppColors.cream)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_lessons.isEmpty)
                Text('Пока нет уроков — добавьте ссылку или видео.',
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.6))),
              for (final (i, l) in _lessons.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    radius: 14,
                    padding:
                        const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.gold, width: 1),
                          ),
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.goldLight)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(l.title,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              Text(l.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white
                                          .withValues(alpha: 0.55))),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              setState(() => _lessons.removeAt(i)),
                          icon: Icon(Icons.delete_outline,
                              size: 20,
                              color: Colors.redAccent
                                  .withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: _save,
                  child: const Text('Сохранить курс',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
