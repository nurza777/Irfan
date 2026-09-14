// Временная точка входа для съёмки скриншотов витрины.
//
// В боевую сборку не попадает: собирается только явным указанием цели,
//
//   flutter build ios --simulator --debug \
//     -t tools/screenshots_main.dart --dart-define=SHOT=tracker
//
// Нужна потому, что снять экраны обычным способом нельзя: `simctl` умеет
// делать снимок, но не умеет нажимать, а `idb` на этой машине не стоит.
// Здесь приложение поднимается ровно так же, как в `lib/main.dart`, и сразу
// показывает нужный экран — без единого нажатия.
//
// Экраны, которые в приложении лежат внутри PageView корневого экрана
// (трекер, зикры), своего Scaffold и фона не имеют, поэтому обёрнуты здесь.
// Остальные открываются как отдельные маршруты и приносят их с собой.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:irfan/app_state.dart';
import 'package:irfan/screens/azkar_screen.dart';
import 'package:irfan/screens/courses_page.dart';
import 'package:irfan/screens/teacher_courses_page.dart';
import 'package:irfan/screens/names_screen.dart';
import 'package:irfan/screens/root_screen.dart';
import 'package:irfan/screens/surah_screen.dart';
import 'package:irfan/screens/tracker_page.dart';
import 'package:irfan/screens/zikr_page.dart';
import 'package:irfan/services/access_service.dart';
import 'package:irfan/services/courses_service.dart';
import 'package:irfan/services/visual_effects.dart';
import 'package:irfan/services/voice_service.dart';
import 'package:irfan/theme.dart';
import 'package:irfan/widgets/dome_background.dart';

const _shot = String.fromEnvironment('SHOT', defaultValue: 'main');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefsFuture = SharedPreferences.getInstance();
  await Future.wait([
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    initializeDateFormatting('ru'),
    VoiceService.instance.loadCatalog(),
    prefsFuture,
  ]);
  final prefs = await prefsFuture;
  VisualEffects.instance.load(prefs);

  // Онбординг для съёмки всегда считаем пройденным: иначе первый кадр —
  // приветствие, а не экран, который нужен.
  await prefs.setBool('onboarding_done', true);

  final state = AppState();
  state.init();

  runApp(AppScope(
    state: state,
    child: MaterialApp(
      title: 'Ирфан',
      debugShowCheckedModeBanner: false,
      theme: buildIrfanTheme(),
      home: _screen(),
    ),
  ));
}

Widget _screen() {
  switch (_shot) {
    case 'tracker':
      return const _Framed(TrackerPage());
    case 'zikr':
      return const _Framed(ZikrPage());
    case 'quran':
      return const SurahScreen(surah: 1);
    case 'names':
      return const NamesScreen();
    case 'azkar':
      return const AzkarScreen();
    case 'courses':
      return const CoursesPage();
    case 'lessons':
      // Список уроков внутри устаза: сам экран курсов почти пуст (одна
      // карточка на весь экран), а витрине нужно показать уроки.
      return const _Lessons();
    default:
      return const RootScreen();
  }
}

/// Обёртка для страниц из PageView: они рассчитывают, что фон и Scaffold
/// им даёт корневой экран.
class _Framed extends StatelessWidget {
  final Widget child;
  const _Framed(this.child);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: DomeBackground(child: SafeArea(child: child)),
      );
}

/// Каталог уроков первого устаза. Экран требует уже загруженные данные,
/// поэтому тянем их сами и показываем, как только пришли.
class _Lessons extends StatefulWidget {
  const _Lessons();

  @override
  State<_Lessons> createState() => _LessonsState();
}

class _LessonsState extends State<_Lessons> {
  TeacherCourses? _teacher;

  @override
  void initState() {
    super.initState();
    CoursesService.fetch().then((catalog) {
      if (!mounted) return;
      final teachers = catalog?.teachers ?? const <TeacherCourses>[];
      final t = teachers.isEmpty ? null : teachers.first;
      if (t != null) _openAccess(t);
      setState(() => _teacher = t);
    });
  }

  /// Открывает все направления устаза.
  ///
  /// Без этого каждый модуль показан замком «Доступ закрыт» — для витрины
  /// это худший возможный кадр, хотя ученику, которому устаз доступ выдал,
  /// экран выглядит иначе.
  ///
  /// Выдача повторяется несколько секунд не от неуверенности: приложение
  /// само отмечается на сервере при старте и ответом приносит список
  /// доступов этого устройства. Ответ приходит позже нашей выдачи и затирает
  /// её пустым списком — поэтому мы возвращаем доступ уже после него.
  void _openAccess(TeacherCourses t) {
    final grants = [
      for (final d in t.directions)
        {'scope': 'direction', 'key': d.title, 'until': null},
    ];
    AccessService.instance.update(grants);
    for (final sec in [2, 4, 6, 8]) {
      Future.delayed(Duration(seconds: sec), () {
        if (mounted) AccessService.instance.update(grants);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _teacher;
    if (t == null) {
      return const Scaffold(
        body: DomeBackground(child: Center(child: CircularProgressIndicator())),
      );
    }
    return TeacherCoursesPage(
      teacherName: t.name,
      teacherBio: t.bio,
      courses: t,
    );
  }
}
