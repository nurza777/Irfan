import 'package:shared_preferences/shared_preferences.dart';

import 'lang.dart';
import 'prayer_service.dart';

/// Мазхаб — влияет на время Асра.
enum AsrMadhab {
  hanafi('Ханафитский'),
  shafi('Шафиитский');

  final String titleRu;
  const AsrMadhab(this.titleRu);
}

/// Метод расчёта времён намаза.
enum CalcMethod {
  muslimWorldLeague('Всемирная мусульманская лига', 'Стандарт для СНГ и Европы'),
  russia('Духовное управление мусульман России', 'Россия'),
  ummAlQura('Умм аль-Кура', 'Саудовская Аравия, Мекка'),
  egyptian('Египетский', 'Египет, Африка'),
  karachi('Карачи', 'Пакистан, Индия, Афганистан'),
  turkiye('Диянет', 'Турция'),
  northAmerica('ISNA', 'Северная Америка');

  final String titleRu;
  final String subtitleRu;
  const CalcMethod(this.titleRu, this.subtitleRu);
}

/// Способ определения города.
enum LocationMode { auto, manual }

/// Город для ручного выбора.
class City {
  final String name;
  final double lat;
  final double lon;
  const City(this.name, this.lat, this.lon);

  AppLocation get location => AppLocation(lat, lon, name);
}

/// Настройки приложения в SharedPreferences.
class SettingsService {
  static const _modeKey = 'settings_location_mode';
  static const _cityKey = 'settings_city';
  static const _madhabKey = 'settings_madhab';
  static const _methodKey = 'settings_method';
  static const _notifyKey = 'settings_notify';
  static const _notifyBeforeKey = 'settings_notify_before';
  static const _notifyPrayersKey = 'settings_notify_prayers';
  static const _langKey = 'settings_lang';

  static const cities = [
    City('Бишкек', 42.8746, 74.5698),
    City('Ош', 40.5283, 72.7985),
    City('Джалал-Абад', 40.9333, 73.0),
    City('Каракол', 42.49, 78.3936),
    City('Нарын', 41.4287, 75.9911),
    City('Талас', 42.5228, 72.2427),
    City('Баткен', 40.0629, 70.8199),
    City('Токмок', 42.8417, 75.2833),
    City('Кара-Балта', 42.8144, 73.8485),
    City('Алматы', 43.2389, 76.8897),
    City('Москва', 55.7558, 37.6173),
    City('Мекка', 21.4225, 39.8262),
  ];

  final SharedPreferences _prefs;
  SettingsService(this._prefs);

  static Future<SettingsService> create() async =>
      SettingsService(await SharedPreferences.getInstance());

  LocationMode get locationMode =>
      LocationMode.values.byNameOr(_prefs.getString(_modeKey)) ??
      LocationMode.auto;

  City get manualCity {
    final name = _prefs.getString(_cityKey);
    return cities.where((c) => c.name == name).firstOrNull ?? cities.first;
  }

  AsrMadhab get madhab =>
      AsrMadhab.values.byNameOr(_prefs.getString(_madhabKey)) ??
      AsrMadhab.hanafi;

  // Метод расчёта зафиксирован для Кыргызстана/СНГ (выбор убран из настроек).
  CalcMethod get method => CalcMethod.muslimWorldLeague;

  Future<void> setLocationMode(LocationMode m) =>
      _prefs.setString(_modeKey, m.name);
  Future<void> setManualCity(City c) => _prefs.setString(_cityKey, c.name);
  Future<void> setMadhab(AsrMadhab m) => _prefs.setString(_madhabKey, m.name);
  Future<void> setMethod(CalcMethod m) => _prefs.setString(_methodKey, m.name);

  // --- Уведомления о намазе ---

  /// Намазы, по которым можно слать напоминания (без восхода).
  static const notifiablePrayers = [
    PrayerKey.fajr,
    PrayerKey.dhuhr,
    PrayerKey.asr,
    PrayerKey.maghrib,
    PrayerKey.isha,
  ];

  bool get notificationsEnabled => _prefs.getBool(_notifyKey) ?? false;

  /// За сколько минут до намаза напоминать (0 — точно во время намаза).
  int get notifyBeforeMinutes => _prefs.getInt(_notifyBeforeKey) ?? 0;

  Set<PrayerKey> get notifyPrayers {
    final list = _prefs.getStringList(_notifyPrayersKey);
    if (list == null) return notifiablePrayers.toSet();
    return list
        .map((n) => PrayerKey.values.byNameOr(n))
        .whereType<PrayerKey>()
        .toSet();
  }

  Future<void> setNotificationsEnabled(bool v) =>
      _prefs.setBool(_notifyKey, v);
  Future<void> setNotifyBeforeMinutes(int v) =>
      _prefs.setInt(_notifyBeforeKey, v.clamp(0, 60));
  Future<void> setNotifyPrayers(Set<PrayerKey> p) => _prefs.setStringList(
      _notifyPrayersKey, p.map((e) => e.name).toList());

  // --- Язык ---

  Lang get lang =>
      Lang.values.byNameOr(_prefs.getString(_langKey)) ?? Lang.ru;

  Future<void> setLang(Lang l) => _prefs.setString(_langKey, l.name);
}

extension _ByNameOr<T extends Enum> on List<T> {
  T? byNameOr(String? name) =>
      name == null ? null : where((e) => e.name == name).firstOrNull;
}
