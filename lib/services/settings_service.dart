import 'dart:convert';

import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart' as geocoding;
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

  /// Города для ручного выбора.
  ///
  /// Раньше их было двенадцать, и человек из Кызыл-Кии или Узгена не находил
  /// себя вовсе — оставалось «Автоматически», то есть отдать геопозицию,
  /// чего он мог не хотеть. Список — областные центры и города Кыргызстана
  /// плюс те места, куда уезжают работать; всё остальное ищется по названию
  /// (см. [findCity]), а найденное сохраняется вместе с координатами.
  static const cities = [
    City('Бишкек', 42.8746, 74.5698),
    City('Ош', 40.5283, 72.7985),
    City('Джалал-Абад', 40.9333, 73.0),
    City('Каракол', 42.4907, 78.3936),
    City('Нарын', 41.4287, 75.9911),
    City('Талас', 42.5228, 72.2427),
    City('Баткен', 40.0629, 70.8199),
    City('Токмок', 42.8417, 75.2833),
    City('Кара-Балта', 42.8144, 73.8485),
    City('Кант', 42.8911, 74.8508),
    City('Сокулук', 42.8667, 74.2833),
    City('Беловодское', 42.8253, 73.7767),
    City('Каинды', 42.8167, 73.7),
    City('Шопоков', 42.8333, 74.3833),
    City('Балыкчы', 42.4606, 76.1856),
    City('Чолпон-Ата', 42.65, 77.0833),
    City('Кочкор', 42.2167, 75.75),
    City('Ат-Баши', 41.1706, 75.8083),
    City('Кара-Суу', 40.7031, 72.8656),
    City('Узген', 40.7714, 73.3),
    City('Ноокат', 40.2667, 72.6167),
    City('Кызыл-Кия', 40.2569, 72.13),
    City('Сулюкта', 39.9386, 69.5672),
    City('Исфана', 39.8419, 69.53),
    City('Кербен', 41.4869, 71.7539),
    City('Ала-Бука', 41.4, 71.4667),
    City('Майлуу-Суу', 41.2733, 72.4667),
    City('Таш-Кумыр', 41.3472, 72.2139),
    City('Кара-Куль', 41.6167, 72.6667),
    City('Кочкор-Ата', 41.0333, 72.4833),
    City('Токтогул', 41.8742, 72.9414),
    City('Алматы', 43.2389, 76.8897),
    City('Астана', 51.1694, 71.4491),
    City('Шымкент', 42.3417, 69.5901),
    City('Тараз', 42.9, 71.3667),
    City('Ташкент', 41.2995, 69.2401),
    City('Андижан', 40.7821, 72.3442),
    City('Худжанд', 40.2833, 69.6333),
    City('Душанбе', 38.5598, 68.787),
    City('Москва', 55.7558, 37.6173),
    City('Санкт-Петербург', 59.9311, 30.3609),
    City('Екатеринбург', 56.8389, 60.6057),
    City('Новосибирск', 55.0084, 82.9357),
    City('Казань', 55.7963, 49.1088),
    City('Красноярск', 56.0153, 92.8932),
    City('Стамбул', 41.0082, 28.9784),
    City('Дубай', 25.2048, 55.2708),
    City('Джидда', 21.4858, 39.1925),
    City('Мекка', 21.4225, 39.8262),
    City('Медина', 24.4686, 39.6142),
  ];

  /// Первые в списке — их видно сразу, без открытия поиска.
  static const quickCities = 8;

  /// Ищет город по названию системным геокодером.
  ///
  /// Нужен для всего, чего нет во встроенном списке — села, город за
  /// границей. Возвращает null, если ничего не нашлось или нет связи: это
  /// разные причины для человека, но для экрана — одно и то же «не нашли»,
  /// а обещать «проверьте интернет» там, где просто нет такого села,
  /// значит врать.
  static Future<City?> findCity(String query) async {
    final name = query.trim();
    if (name.length < 2) return null;
    try {
      final found = await geocoding.Geocoding()
          .locationFromAddress(name, locale: const Locale('ru'))
          .timeout(const Duration(seconds: 10));
      if (found.isEmpty) return null;
      final l = found.first;
      // Имя берём то, что набрал человек: геокодер отдаёт только координаты,
      // а подписывать город чужим языком (или пустой строкой) хуже.
      return City(_titleCase(name), l.latitude, l.longitude);
    } catch (_) {
      return null;
    }
  }

  static String _titleCase(String v) =>
      v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);

  final SharedPreferences _prefs;
  SettingsService(this._prefs);

  static Future<SettingsService> create() async =>
      SettingsService(await SharedPreferences.getInstance());

  LocationMode get locationMode =>
      LocationMode.values.byNameOr(_prefs.getString(_modeKey)) ??
      LocationMode.auto;

  /// Выбранный вручную город.
  ///
  /// В настройках лежит либо имя из [cities] (так писали прежние сборки),
  /// либо JSON с координатами — найденный по названию город в списке не
  /// значится, и восстановить его по имени неоткуда.
  City get manualCity {
    final raw = _prefs.getString(_cityKey);
    if (raw == null) return cities.first;
    if (raw.startsWith('{')) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final name = (j['name'] as String?)?.trim() ?? '';
        final lat = (j['lat'] as num?)?.toDouble();
        final lon = (j['lon'] as num?)?.toDouble();
        if (name.isNotEmpty && lat != null && lon != null) {
          return City(name, lat, lon);
        }
      } catch (_) {
        // Испорченная запись не должна оставлять человека без времени
        // намаза — молча откатываемся на первый город.
      }
      return cities.first;
    }
    return cities.where((c) => c.name == raw).firstOrNull ?? cities.first;
  }

  AsrMadhab get madhab =>
      AsrMadhab.values.byNameOr(_prefs.getString(_madhabKey)) ??
      AsrMadhab.hanafi;

  // Метод расчёта зафиксирован для Кыргызстана/СНГ (выбор убран из настроек).
  CalcMethod get method => CalcMethod.muslimWorldLeague;

  Future<void> setLocationMode(LocationMode m) =>
      _prefs.setString(_modeKey, m.name);
  /// Пишем вместе с координатами: имя само по себе ничего не значит для
  /// города, которого нет во встроенном списке.
  Future<void> setManualCity(City c) => _prefs.setString(
      _cityKey, jsonEncode({'name': c.name, 'lat': c.lat, 'lon': c.lon}));
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
