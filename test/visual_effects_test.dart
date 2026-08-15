import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:irfan/services/lang.dart';
import 'package:irfan/services/visual_effects.dart';

/// Уровень оформления решает, рисуется ли размытие за каждой карточкой —
/// самая дорогая операция в приложении. Ошибка здесь не падает, а тихо
/// возвращает тяжёлый режим на слабых телефонах, поэтому закреплено тестом.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => appLang = Lang.ru);

  test('сохранённый уровень поднимается из настроек', () async {
    SharedPreferences.setMockInitialValues(
        {VisualEffects.prefsKey: 'light'});
    VisualEffects.instance.load(await SharedPreferences.getInstance());

    expect(VisualEffects.instance.level, EffectsLevel.light);
    expect(VisualEffects.instance.blur, isFalse);
    expect(VisualEffects.instance.animated, isFalse);
  });

  test('без записи берётся уровень по умолчанию для платформы', () async {
    SharedPreferences.setMockInitialValues({});
    VisualEffects.instance.load(await SharedPreferences.getInstance());

    expect(VisualEffects.instance.level, VisualEffects.defaultLevel);
  });

  test('мусор в настройках не оставляет приложение без оформления', () async {
    SharedPreferences.setMockInitialValues(
        {VisualEffects.prefsKey: 'сверхполное'});
    VisualEffects.instance.load(await SharedPreferences.getInstance());

    expect(VisualEffects.instance.level, VisualEffects.defaultLevel);
  });

  test('смена уровня сохраняется и будит слушателей', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    VisualEffects.instance.load(prefs);

    var notified = 0;
    void listener() => notified++;
    VisualEffects.instance.addListener(listener);
    addTearDown(() => VisualEffects.instance.removeListener(listener));

    await VisualEffects.instance.setLevel(EffectsLevel.light);
    expect(notified, 1);
    expect(prefs.getString(VisualEffects.prefsKey), 'light');

    // Повторная установка того же уровня ничего не будит: на неё подписаны
    // все стеклянные карточки на экране.
    await VisualEffects.instance.setLevel(EffectsLevel.light);
    expect(notified, 1);

    await VisualEffects.instance.setLevel(EffectsLevel.full);
    expect(notified, 2);
    expect(prefs.getString(VisualEffects.prefsKey), 'full');
  });

  test('подписи переключателя переведены на кыргызский', () {
    appLang = Lang.ky;
    // Соседние литералы склеиваются — ключ словаря должен совпадать со
    // склеенной строкой, иначе перевод молча не находится.
    const hint = 'Матовое стекло и живые обои. Красивее, но на слабых '
        'телефонах приложение может подтормаживать.';
    for (final ru in [
      'Оформление',
      'Полное',
      'Экономное',
      hint,
      'Без размытия и движения обоев. Выглядит проще, зато листается плавно.',
    ]) {
      expect(t(ru), isNot(ru), reason: 'нет перевода: $ru');
    }
  });
}
