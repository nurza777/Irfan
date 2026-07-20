import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'prayer_service.dart';

/// Статус намаза в трекере.
enum PrayerStatus { pending, read, missed }

/// Трекер намазов: хранит отметки по дням в SharedPreferences.
/// Через 10 минут после наступления времени намаза приложение спрашивает,
/// прочитан ли он.
class TrackerService {
  static const Duration askDelay = Duration(minutes: 10);
  static const _keyPrefix = 'tracker_';

  final SharedPreferences _prefs;
  TrackerService(this._prefs);

  static Future<TrackerService> create() async =>
      TrackerService(await SharedPreferences.getInstance());

  String _dayKey(DateTime day) =>
      '$_keyPrefix${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  Map<String, String> _readDay(DateTime day) {
    final raw = _prefs.getString(_dayKey(day));
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> setStatus(DateTime day, PrayerKey prayer, PrayerStatus status) async {
    final map = _readDay(day);
    map[prayer.name] = status.name;
    await _prefs.setString(_dayKey(day), jsonEncode(map));
  }

  PrayerStatus statusOf(DateTime day, PrayerKey prayer) {
    final v = _readDay(day)[prayer.name];
    return PrayerStatus.values
            .where((s) => s.name == v)
            .cast<PrayerStatus?>()
            .firstOrNull ??
        PrayerStatus.pending;
  }

  /// Первый намаз, по которому пора спросить: время + 10 мин прошло,
  /// а отметки ещё нет.
  PrayerKey? dueQuestion(DayPrayerTimes times, DateTime now) {
    for (final k in PrayerKey.values.where((k) => k.isPrayer)) {
      final askAt = times[k].add(askDelay);
      if (now.isAfter(askAt) &&
          statusOf(times.date, k) == PrayerStatus.pending) {
        return k;
      }
    }
    return null;
  }

  /// Сколько намазов прочитано за день (для недельной статистики).
  int readCount(DateTime day) {
    final map = _readDay(day);
    return map.values.where((v) => v == PrayerStatus.read.name).length;
  }
}
