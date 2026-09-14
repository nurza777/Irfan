import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'prayer_service.dart';

/// Статус намаза в трекере.
///
/// [restored] — «каза», намаз, прочитанный позже пропущенного времени.
/// Держим отдельным значением, а не приравниваем к [read]: восстановленный
/// намаз — не то же самое, что прочитанный вовремя, и в статистике человек
/// должен видеть разницу. Старые записи значения не знают и читаются как
/// прежде: неизвестный статус превращается в [pending].
enum PrayerStatus { pending, read, missed, restored }

/// Пропущенный намаз, который можно восстановить.
class MissedPrayer {
  final DateTime day;
  final PrayerKey prayer;
  const MissedPrayer(this.day, this.prayer);
}

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

  String _dayKey(DateTime day) => '$_keyPrefix${dayKeyOf(day)}';

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
    final key = _dayKey(day);
    await _prefs.setString(key, jsonEncode(map));
    // Сейчас пишется только сегодняшний день, но если появится правка
    // задним числом — кэш прошлых дней обязан протухнуть.
    if (key != _dayKey(DateTime.now())) _pastReadFor = null;
  }

  /// Записывает ответ на вопрос «прочитали ли вы намаз», не требуя живого
  /// [TrackerService].
  ///
  /// Нужно потому, что кнопки «Да»/«Нет» человек нажимает в уведомлении при
  /// закрытом приложении: обработчик выполняется в ОТДЕЛЬНОМ изоляте, где
  /// нет ни состояния приложения, ни его сервисов. Формат ключа и значения
  /// здесь ровно тот же, что и у [setStatus] — потому и вынесено в общее
  /// место, а не переписано во второй раз.
  static Future<void> applyAnswer(String dayKey, String prayerName,
      PrayerStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    // Значение могли изменить в другом изоляте, пока этот жил в памяти.
    await prefs.reload();
    final key = '$_keyPrefix$dayKey';
    Map<String, String> map = {};
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        map = Map<String, String>.from(jsonDecode(raw) as Map);
      } catch (_) {
        map = {};
      }
    }
    map[prayerName] = status.name;
    await prefs.setString(key, jsonEncode(map));
  }

  /// Ключ дня в том виде, в каком он уходит в уведомление и возвращается
  /// из него. Отдельный метод, чтобы формат не разъехался.
  static String dayKeyOf(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  /// Перечитывает хранилище: ответы могли прийти из уведомления, пока
  /// приложение было в фоне, и в памяти лежат устаревшие значения.
  Future<void> reload() => _prefs.reload();

  PrayerStatus statusOf(DateTime day, PrayerKey prayer) {
    final v = _readDay(day)[prayer.name];
    return PrayerStatus.values
            .where((s) => s.name == v)
            .cast<PrayerStatus?>()
            .firstOrNull ??
        PrayerStatus.pending;
  }

  /// Первый намаз, по которому пора спросить: время + задержка прошло,
  /// а отметки ещё нет.
  ///
  /// [delay] приходит из настроек — та же величина, по которой ставится
  /// уведомление с кнопками. Иначе карточка на главной и уведомление
  /// спрашивали бы в разное время.
  PrayerKey? dueQuestion(DayPrayerTimes times, DateTime now,
      {Duration? delay}) {
    for (final k in PrayerKey.values.where((k) => k.isPrayer)) {
      final askAt = times[k].add(delay ?? askDelay);
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
  /// Восстановленные сюда НЕ попадают: человек их прочитал, пусть и позже.
  int missedCount(DateTime day) {
    final map = _readDay(day);
    return map.values.where((v) => v == PrayerStatus.missed.name).length;
  }

  /// Сколько намазов восстановлено за день.
  int restoredCount(DateTime day) {
    final map = _readDay(day);
    return map.values.where((v) => v == PrayerStatus.restored.name).length;
  }

  /// Пропущенные намазы за всю историю — свежие сверху.
  ///
  /// Список для экрана восстановления. Потолок нужен: у человека, который
  /// год отмечал пропуски, накопятся тысячи записей, и построить их все
  /// разом — заметная пауза на ровном месте.
  List<MissedPrayer> missedPrayers({int limit = 300}) {
    final days = _prefs
        .getKeys()
        .where((k) => k.startsWith(_keyPrefix))
        .map(_dateFromKey)
        .whereType<DateTime>()
        .toList()
      ..sort((a, b) => b.compareTo(a));   // свежие первыми
    final out = <MissedPrayer>[];
    for (final d in days) {
      final map = _readDay(d);
      for (final k in PrayerKey.values.where((k) => k.isPrayer)) {
        if (map[k.name] == PrayerStatus.missed.name) {
          out.add(MissedPrayer(d, k));
          if (out.length >= limit) return out;
        }
      }
    }
    return out;
  }

  /// Сколько всего намазов отмечено прочитанными за всю историю
  /// (для коинов: 1 намаз = 5 баллов).
  // Прошлые дни не меняются — считаем их один раз за день, а перечитываем
  // только сегодняшнюю запись (см. такой же приём в ZikrService).
  int? _pastRead;
  String? _pastReadFor;

  int totalReadCount() {
    int readIn(String raw) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        return map.values.where((v) => v == PrayerStatus.read.name).length;
      } catch (_) {
        return 0;
      }
    }

    final todayKey = _dayKey(DateTime.now());
    if (_pastReadFor != todayKey) {
      var past = 0;
      for (final key in _prefs.getKeys()) {
        if (!key.startsWith(_keyPrefix) || key == todayKey) continue;
        final raw = _prefs.getString(key);
        if (raw != null) past += readIn(raw);
      }
      _pastRead = past;
      _pastReadFor = todayKey;
    }

    final todayRaw = _prefs.getString(todayKey);
    return _pastRead! + (todayRaw == null ? 0 : readIn(todayRaw));
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

    var read = 0, missed = 0, restored = 0, fullDays = 0;
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
        } else if (v == PrayerStatus.restored.name) {
          restored++;
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
      restored: restored,
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

  /// Прочитанные позже срока. Считаются отдельно от [read] — см. описание
  /// [PrayerStatus.restored].
  final int restored;
  final int fullDays;
  final Map<PrayerKey, int> readByPrayer;
  const PeriodStats({
    required this.from,
    required this.to,
    required this.days,
    required this.read,
    required this.missed,
    required this.restored,
    required this.fullDays,
    required this.readByPrayer,
  });

  int get totalPossible => days * 5;

  /// Доля прочитанных от всех возможных намазов (0..1).
  double get readRatio =>
      totalPossible == 0 ? 0 : read / totalPossible;
}
