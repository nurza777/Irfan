import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/app_state.dart';
import 'package:irfan/main.dart';
import 'package:irfan/services/lang.dart';

void main() {
  testWidgets('Онбординг показывается на первом запуске', (tester) async {
    await tester.pumpWidget(IrfanApp(state: AppState(), onboardingDone: false));
    expect(find.text('ПРОДОЛЖИТЬ'), findsOneWidget);
    // Дренируем отложенный таймер анимации FadeSlideIn (Future.delayed),
    // иначе тест падает с «pending timer». Фоновые .repeat()-анимации —
    // тикеры, они гасятся при разборке дерева.
    await tester.pump(const Duration(seconds: 1));
  });

  // Размеры настоящих экранов. Поверхность теста по умолчанию 800×600 — на
  // ней первый экран не помещается по высоте, и нажатие на язык мимо: этого
  // не бывает ни на одном телефоне, а проверка ничего бы не проверила.
  // Самый маленький — первый iPhone SE: сборка поддерживает iOS 13.
  const screens = {
    'iPhone SE (1-го поколения)': Size(320, 568),
    'iPhone SE (2–3-го поколения)': Size(375, 667),
    'iPhone 17 Pro': Size(402, 874),
  };
  for (final entry in screens.entries) {
    testWidgets(
      'на первом экране выбирают язык, и экран сразу на нём — ${entry.key}',
      (tester) async {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = entry.value * 2;
        addTearDown(tester.view.reset);
        // Нажатие мимо кнопки должно ронять проверку, а не молча проходить.
        WidgetController.hitTestWarningShouldBeFatal = true;
        addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

        appLang = Lang.ru;
        await tester.pumpWidget(
          IrfanApp(state: AppState(), onboardingDone: false),
        );
        // Два кадра, а не один: блоки экрана появляются с задержкой, и в
        // первом кадре после неё анимация только стартует — кнопка ещё
        // сдвинута, и нажатие по её прежним координатам уходит мимо.
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        // Экран помещается: переполнение Flutter сообщает исключением.
        expect(tester.takeException(), isNull);
        // Оба языка предложены своими названиями — их узнают без перевода.
        expect(find.text('Русский'), findsOneWidget);
        expect(find.text('Кыргызча'), findsOneWidget);

        // На маленьком экране выбор языка может оказаться ниже края — человек
        // до него докрутит, и проверка делает то же.
        await tester.ensureVisible(find.text('Кыргызча'));
        await tester.pump();
        await tester.tap(find.text('Кыргызча'));
        await tester.pump();
        expect(appLang, Lang.ky);
        expect(find.text('УЛАНТУУ'), findsOneWidget);
        expect(find.text('ПРОДОЛЖИТЬ'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.text('Русский'));
        await tester.pump();
        await tester.tap(find.text('Русский'));
        await tester.pump();
        expect(find.text('ПРОДОЛЖИТЬ'), findsOneWidget);
        appLang = Lang.ru;
      },
    );
  }
}
