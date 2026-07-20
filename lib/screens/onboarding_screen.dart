import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../widgets/dome_background.dart';
import 'root_screen.dart';

/// Первый запуск: объясняем, зачем геолокация, и просим разрешение.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _busy = false;

  Future<void> _continue() async {
    setState(() => _busy = true);
    final state = AppScope.of(context);
    await state.init(); // запросит разрешение на локацию
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RootScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DomeBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Image.asset('assets/images/logo.png',
                    height: 110,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                const SizedBox(height: 40),
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                        fontSize: 30,
                        height: 1.35,
                        color: Colors.white.withValues(alpha: 0.9)),
                    children: const [
                      TextSpan(text: 'Мы используем\n'),
                      TextSpan(
                          text: 'Службу Геолокации,\n',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(
                          text:
                              'чтобы автоматически определить ваш город и рассчитать время намаза.'),
                    ],
                  ),
                ),
                const Spacer(),
                Center(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _continue,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 1.5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 44, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('ПРОДОЛЖИТЬ',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
