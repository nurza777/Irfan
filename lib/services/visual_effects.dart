import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Уровень оформления.
///
/// `full` — стекло как задумано: за каждой карточкой размывается фон, обои
/// медленно приближаются, над ними летят частицы.
/// `light` — те же цвета и та же вёрстка, но без размытия и без вечных
/// анимаций. Экран выглядит почти так же, а рисуется в разы дешевле.
enum EffectsLevel { full, light }

/// Переключатель тяжёлого оформления.
///
/// Живёт синглтоном, а не в [SettingsService], потому что его читают
/// `DomeBackground` и `GlassCard` — они строятся вне `AppScope` (фон рисуется
/// раньше, чем появляется состояние приложения), ровно как обои.
///
/// **Почему на Android по умолчанию `light`.** `BackdropFilter` — самая
/// дорогая операция во всём приложении: каждая стеклянная карточка заставляет
/// движок отдельно скопировать и размыть то, что под ней. Карточек на экране
/// до шести (в чтении Корана — по одной на каждый аят в списке), и при
/// прокрутке размытие пересчитывается каждый кадр. На iPhone это тянет любой
/// аппарат, начиная со старых; на Android разброс устройств огромный, и на
/// части из них движок работает не на Vulkan, а на GL, где такое размытие
/// стоит ещё дороже. Пользователь всегда может вернуть полное оформление в
/// настройках.
class VisualEffects extends ChangeNotifier {
  static final VisualEffects instance = VisualEffects._();
  VisualEffects._();

  static const prefsKey = 'settings_effects';

  SharedPreferences? _prefs;
  EffectsLevel _level = defaultLevel;

  EffectsLevel get level => _level;

  /// Размывать ли фон за стеклянными карточками и листами.
  bool get blur => _level == EffectsLevel.full;

  /// Оживлять ли обои (приближение + частицы) и мелкие вечные анимации.
  bool get animated => _level == EffectsLevel.full;

  static EffectsLevel get defaultLevel =>
      !kIsWeb && Platform.isAndroid ? EffectsLevel.light : EffectsLevel.full;

  /// Читается из уже открытых настроек в `main`, до первого кадра: фон и
  /// карточки спрашивают уровень синхронно, при построении.
  void load(SharedPreferences prefs) {
    _prefs = prefs;
    final saved = prefs.getString(prefsKey);
    _level = EffectsLevel.values
            .where((e) => e.name == saved)
            .firstOrNull ??
        defaultLevel;
  }

  Future<void> setLevel(EffectsLevel value) async {
    if (value == _level) return;
    _level = value;
    notifyListeners();
    await _prefs?.setString(prefsKey, value.name);
  }
}
