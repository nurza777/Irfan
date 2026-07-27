import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/app_state.dart';
import 'package:irfan/main.dart';

void main() {
  testWidgets('Онбординг показывается на первом запуске', (tester) async {
    await tester.pumpWidget(IrfanApp(state: AppState(), onboardingDone: false));
    expect(find.text('ПРОДОЛЖИТЬ'), findsOneWidget);
    // Дренируем отложенный таймер анимации FadeSlideIn (Future.delayed),
    // иначе тест падает с «pending timer». Фоновые .repeat()-анимации —
    // тикеры, они гасятся при разборке дерева.
    await tester.pump(const Duration(seconds: 1));
  });
}
