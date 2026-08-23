import 'package:flutter/material.dart';

import '../services/courses_service.dart';
import '../services/lang.dart';
import '../services/teachers_service.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import 'teacher_courses_page.dart';

/// Курсы: сначала выбираем устаза, дальше смотрим его уроки.
///
/// Устазы приходят из реестра `teachers.json` (регистрируются сами в своём
/// приложении, ученикам видны после одобрения админом), уроки — из
/// `courses.json`, где у каждого устаза свой блок. Одобренный устаз без
/// уроков в списке остаётся: он есть, просто ещё ничего не выложил.
class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _TeacherEntry {
  final String name;
  final String bio;
  final TeacherCourses? courses;

  const _TeacherEntry({required this.name, required this.bio, this.courses});

  int get courseCount => courses?.courseCount ?? 0;
  int get lessonCount => courses?.lessonCount ?? 0;

  /// Показывать ли карточку ученику.
  ///
  /// Учётку устаза заводит админ, и сервер сразу ставит ей `approved`
  /// (`_staff_op` → `_set_teacher_status`) — то есть в списке оказывается
  /// каждый выданный логин, включая служебные. Так в каталог попала карточка
  /// «App Review», заведённая для проверки Apple: ученик видел её наравне с
  /// настоящими устазами.
  ///
  /// Правило: карточка нужна, если за ней что-то есть — уроки или хотя бы
  /// рассказ о себе. Пустая запись без описания ведёт на экран «здесь пока
  /// пусто», то есть это тупик, а не раздел.
  bool get visible => lessonCount > 0 || courseCount > 0 || bio.isNotEmpty;
}

class _CoursesPageState extends State<CoursesPage> {
  List<_TeacherEntry>? _entries;
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Сперва — сохранённое с прошлого захода: список появляется сразу, а не
    // после запроса на сервер. Если заходов ещё не было, останется кружок.
    final saved = await Future.wait([
      CoursesService.cached(),
      TeachersService.cached(),
    ]);
    if (!mounted) return;
    final savedCatalog = saved[0] as Catalog?;
    final savedRegistry = saved[1] as List<Teacher>?;
    final hadSaved = savedCatalog != null || savedRegistry != null;
    if (hadSaved) {
      setState(() {
        _entries = _merge(savedCatalog, savedRegistry);
        _loading = false;
      });
    }

    // Реестр и каталог тянем разом: это два запроса к одному серверу,
    // и ждать их по очереди значит удваивать паузу.
    final results = await Future.wait([
      CoursesService.fetch(),
      TeachersService.fetch(),
    ]);
    if (!mounted) return;
    final catalog = results[0] as Catalog?;
    final registry = results[1] as List<Teacher>?;
    // Сеть не ответила, а сохранённое есть — оставляем его на экране:
    // подменять уроки заглушкой «нет связи» было бы шагом назад.
    if (catalog == null && registry == null && hadSaved) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _offline = catalog == null && registry == null;
      _entries = _merge(catalog, registry);
      _loading = false;
    });
  }

  /// Сводим реестр и каталог. Неодобренных и заблокированных не показываем;
  /// блок в каталоге без записи в реестре (опубликован админом напрямую или
  /// остался от прежнего формата) показываем — эти уроки уже прошли проверку.
  List<_TeacherEntry> _merge(Catalog? catalog, List<Teacher>? registry) {
    final known = {for (final t in registry ?? const <Teacher>[]) t.id: t};
    final out = <_TeacherEntry>[];
    final used = <String>{};
    // Блок каталога прежнего вида: у него нет id, только имя автора. Пока
    // устаз не опубликовал каталог заново, узнать его можно лишь по имени —
    // иначе один и тот же человек стоял бы в списке дважды: записью из
    // реестра и своими же старыми уроками.
    final legacy = catalog?.byId(Catalog.legacyTeacherId);
    var legacyTaken = false;
    String key(String s) => s.trim().toLowerCase();

    for (final rec in registry ?? const <Teacher>[]) {
      if (!rec.approved) continue;
      used.add(rec.id);
      var block = catalog?.byId(rec.id);
      if (block == null &&
          legacy != null &&
          !legacyTaken &&
          key(legacy.name) == key(rec.name)) {
        block = legacy;
        legacyTaken = true;
      }
      out.add(_TeacherEntry(
        name: rec.name.isEmpty ? t('Устаз') : rec.name,
        bio: rec.bio,
        courses: block,
      ));
    }
    if (legacyTaken) used.add(Catalog.legacyTeacherId);
    for (final block in catalog?.teachers ?? const <TeacherCourses>[]) {
      if (used.contains(block.id)) continue;
      final rec = known[block.id];
      if (rec != null && !rec.approved) continue;
      out.add(_TeacherEntry(
        name: block.name.isEmpty ? t('Устаз') : block.name,
        bio: block.bio,
        courses: block,
      ));
    }
    return [for (final e in out) if (e.visible) e];
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
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
            : _offline
                ? _message(t(
                    'Сервер курсов недоступен.\nПроверьте интернет и обновите.'))
                : (entries == null || entries.isEmpty)
                    ? _message(t(
                        'Устазов пока нет.\nОни появятся после регистрации и проверки.'))
                    : ListView(
                        padding: EdgeInsets.fromLTRB(16,
                            MediaQuery.of(context).padding.top + 72, 16, 16),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 10),
                            child: Text(t('Выберите устаза'),
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700)),
                          ),
                          for (final (i, e) in entries.indexed)
                            _TeacherCard(entry: e, index: i),
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
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, color: AppColors.goldLight),
                label: Text(t('Обновить'),
                    style: const TextStyle(color: AppColors.goldLight)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeacherCard extends StatelessWidget {
  final _TeacherEntry entry;
  final int index;
  const _TeacherCard({required this.entry, required this.index});

  @override
  Widget build(BuildContext context) {
    final name = entry.name.trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FadeSlideIn(
        delay: Duration(milliseconds: 80 * index),
        child: GlassCard(
          radius: 16,
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            leading: Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.domeGreen.withValues(alpha: 0.55),
                border: Border.all(color: AppColors.gold, width: 1),
              ),
              child: Text(initial,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.cream)),
            ),
            title: Text(entry.name,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                entry.bio.isNotEmpty
                    ? entry.bio
                    : entry.lessonCount == 0
                        ? t('Уроки скоро появятся')
                        : '${entry.courseCount} ${t('курс(ов)')} · ${entry.lessonCount} ${t('урок(ов)')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, color: Colors.white.withValues(alpha: 0.65)),
              ),
            ),
            trailing: const Icon(Icons.chevron_right, color: AppColors.gold),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TeacherCoursesPage(
                          teacherName: entry.name,
                          teacherBio: entry.bio,
                          courses: entry.courses,
                        ))),
          ),
        ),
      ),
    );
  }
}
