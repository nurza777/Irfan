import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../services/lang.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import 'root_screen.dart';

/// Первый запуск: выбор языка, объяснение, зачем геолокация, и разрешение.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _busy = false;

  /// Язык, на котором продолжить. Раньше его здесь не спрашивали: всё
  /// открывалось по-русски, а переключатель был только в настройках и на
  /// форме регистрации — тот, кому удобнее кыргызский, искал его сам.
  ///
  /// Сразу предлагаем язык телефона, если он кыргызский.
  late Lang _lang =
      PlatformDispatcher.instance.locales.any((l) => l.languageCode == 'ky')
      ? Lang.ky
      : appLang;

  @override
  void initState() {
    super.initState();
    appLang = _lang; // текст экрана — сразу на предложенном языке
  }

  void _pick(Lang l) => setState(() {
    _lang = l;
    appLang = l; // экран переписывается на выбранном языке сразу
  });

  Future<void> _continue() async {
    setState(() => _busy = true);
    final state = AppScope.of(context);
    // Запоминаем выбор ДО init: init читает язык из настроек и иначе
    // вернул бы русский по умолчанию.
    try {
      await (await SettingsService.create()).setLang(_lang);
    } catch (_) {
      // Настройки недоступны — язык останется выбранным до перезапуска.
    }
    if (!mounted) return;
    await state.init(); // запросит разрешение на локацию
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const RootScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DomeBackground(
        child: SafeArea(
          // Экран задуман одной страницей: распорки ставят карточку по
          // центру, а язык и кнопку — вниз. Но на первом iPhone SE или с
          // крупным шрифтом в настройках iOS он не помещается, и выбор языка
          // уходил за нижний край. Поэтому страница прокручивается, когда не
          // влезает, а когда влезает — выглядит как прежде.
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Логотипа здесь нет намеренно: он уже стоит на иконке
                        // приложения, с которой человек сюда и пришёл. Вместо него
                        // распорка — карточка встаёт по центру, между верхом и кнопкой.
                        const Spacer(),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 180),
                          child: GlassCard(
                            radius: 24,
                            padding: const EdgeInsets.all(20),
                            child: Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 27,
                                  height: 1.35,
                                  color: Colors.white.withValues(alpha: 0.92),
                                ),
                                children: [
                                  TextSpan(text: t('Мы используем\n')),
                                  TextSpan(
                                    text: t('Службу Геолокации,\n'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(
                                    text: t(
                                      'чтобы автоматически определить ваш город и рассчитать время намаза.',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Выбор языка — рядом с кнопкой «Продолжить»: на каком языке
                        // выбрали, на том и продолжится. Подпись двуязычная и
                        // НЕ переводится: её должен понять человек, который пока
                        // не видит своего языка на экране.
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 280),
                          // Во всю ширину: иначе блок сжимался бы по кнопкам
                          // и вставал к левому краю вместо середины.
                          child: SizedBox(
                            width: double.infinity,
                            child: Column(
                              children: [
                                const Text(
                                  'На каком языке продолжить?\n'
                                  'Кайсы тилде улантабыз?',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.4,
                                    color: AppColors.textSoft,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Wrap, а не Row: на самом узком экране (первый
                                // iPhone SE) или с крупным шрифтом две кнопки не
                                // влезают в строку — вторая переходит ниже, а не
                                // вылезает за край.
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 12,
                                  runSpacing: 10,
                                  children: [
                                    for (final l in Lang.values)
                                      SelectPill(
                                        label: l.label,
                                        selected: _lang == l,
                                        onTap: () => _pick(l),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Center(
                          child: FadeSlideIn(
                            delay: const Duration(milliseconds: 380),
                            child: PressableScale(
                              child: OutlinedButton(
                                onPressed: _busy ? null : _continue,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.25,
                                  ),
                                  side: const BorderSide(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 44,
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        t('ПРОДОЛЖИТЬ'),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 2,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
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
