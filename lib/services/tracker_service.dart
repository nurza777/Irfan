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

  /// Сколько намазов отмечено пропущенными за день.
  int missedCount(DateTime day) {
    final map = _readDay(day);
    return map.values.where((v) => v == PrayerStatus.missed.name).length;
  }

  /// Сколько всего намазов отмечено прочитанными за всю историю
  /// (для коинов: 1 намаз = 5 баллов).
  int totalReadCount() {
    var total = 0;
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_keyPrefix)) continue;
      final raw = _prefs.getString(key);
      if (raw == null) continue;
      try {
        final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        total += map.values
            .where((v) => v == PrayerStatus.read.name)
            .length;
      } catch (_) {}
    }
    return total;
  }

  /// Все 5 намазов за день отмечены прочитанными.
  bool isFullDay(DateTime day) {
    final map = _readDay(day);
    var read = 0;
    for (final k in PrayerKey.values.where((k) => k.isPrayer)) {
      if (map[k.name] == PrayerStatus.read.name) read++;
    }
    return read == 5;
  }

  /// Текущая серия: подряд идущих «полных» дней (все 5 намазов), считая назад
  /// от сегодня. Незавершённый сегодня серию не рвёт (считаем до вчера).
  int currentStreak() {
    final today = DateTime.now();
    var day = DateTime(today.year, today.month, today.day);
    if (!isFullDay(day)) day = day.subtract(const Duration(days: 1));
    var streak = 0;
    while (isFullDay(day)) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Лучшая серия за всю историю (максимум подряд полных дней).
  int bestStreak() {
    final days = _prefs
        .getKeys()
        .where((k) => k.startsWith(_keyPrefix))
        .map(_dateFromKey)
        .whereType<DateTime>()
        .where(isFullDay)
        .toList()
      ..sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final d in days) {
      if (prev != null && d.difference(prev).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      prev = d;
    }
    return best;
  }

  DateTime? _dateFromKey(String key) {
    final parts = key.substring(_keyPrefix.length).split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]),
        m = int.tryParse(parts[1]),
        d = int.tryParse(parts[2]);
    return (y == null || m == null || d == null) ? null : DateTime(y, m, d);
  }

  /// Сводная статистика за период [from]..[to] включительно (по датам).
  PeriodStats stats(DateTime from, DateTime to) {
    var start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) start = end;
    final totalDays = end.difference(start).inDays + 1;

    var read = 0, missed = 0, fullDays = 0;
    final byPrayer = <PrayerKey, int>{
      for (final k in PrayerKey.values.where((k) => k.isPrayer)) k: 0
    };

    for (var i = 0; i < totalDays; i++) {
      final d = DateTime(start.year, start.month, start.day + i);
      final map = _readDay(d);
      var dayRead = 0;
      for (final k in PrayerKey.values.where((k) => k.isPrayer)) {
        final v = map[k.name];
        if (v == PrayerStatus.read.name) {
          read++;
          dayRead++;
          byPrayer[k] = byPrayer[k]! + 1;
        } else if (v == PrayerStatus.missed.name) {
          missed++;
        }
      }
      if (dayRead == 5) fullDays++;
    }

    return PeriodStats(
      from: start,
      to: end,
      days: totalDays,
      read: read,
      missed: missed,
      fullDays: fullDays,
      readByPrayer: byPrayer,
    );
  }
}

/// Итоги трекера за период.
class PeriodStats {
  final DateTime from;
  final DateTime to;
  final int days;
  final int read;
  final int missed;
  final int fullDays;
  final Map<PrayerKey, int> readByPrayer;
  const PeriodStats({
    required this.from,
    required this.to,
    required this.days,
    required this.read,
    required this.missed,
    required this.fullDays,
    required this.readByPrayer,
  });

  int get totalPossible => days * 5;

  /// Доля прочитанных от всех возможных намазов (0..1).
  double get readRatio =>
      totalPossible == 0 ? 0 : read / totalPossible;
}
