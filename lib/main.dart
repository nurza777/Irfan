import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'services/crash_reporter.dart';
import 'services/visual_effects.dart';
import 'services/voice_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/root_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ставим до всего остального: падение на старте — самое ценное, что
  // хочется увидеть, и раньше его не видел никто.
  CrashReporter.install();
  // Четыре независимых шага: ориентация, названия месяцев, опись записей и
  // настройки. По очереди они складывались в сумму задержек, хотя ждать друг
  // друга им незачем.
  final prefsFuture = SharedPreferences.getInstance();
  await Future.wait([
    // Все экраны свёрстаны под портрет; альбомная ориентация нужна ровно в
    // одном месте — в полноэкранном плеере урока, и он включает её сам.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    initializeDateFormatting('ru'),
    // Опись записей — до первого кадра: экраны по ней решают,
    // показывать ли кнопку озвучки, и решают синхронно.
    VoiceService.instance.loadCatalog(),
    prefsFuture,
  ]);
  final prefs = await prefsFuture;
  // Уровень оформления — до первого кадра: фон и стеклянные карточки
  // спрашивают его синхронно, при построении.
  VisualEffects.instance.load(prefs);
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;

  final state = AppState();
  if (onboardingDone) {
    // Не ждём: экран покажет загрузку, данные придут через notifyListeners.
    state.init();
  }

  runApp(IrfanApp(state: state, onboardingDone: onboardingDone));
}

class IrfanApp extends StatelessWidget {
  final AppState state;
  final bool onboardingDone;
  const IrfanApp(
      {super.key, required this.state, required this.onboardingDone});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Ирфан',
        debugShowCheckedModeBanner: false,
        theme: buildIrfanTheme(),
        home: onboardingDone ? const RootScreen() : const OnboardingScreen(),
      ),
    );
  }
}
