import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'services/crash_reporter.dart';
import 'services/voice_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/root_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ставим до всего остального: падение на старте — самое ценное, что
  // хочется увидеть, и раньше его не видел никто.
  CrashReporter.install();
  // Все экраны свёрстаны под портрет; альбомная ориентация нужна ровно в
  // одном месте — в полноэкранном плеере урока, и он включает её сам.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('ru');
  // Опись записей — до первого кадра: экраны по ней решают,
  // показывать ли кнопку озвучки, и решают синхронно.
  await VoiceService.instance.loadCatalog();
  final prefs = await SharedPreferences.getInstance();
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
