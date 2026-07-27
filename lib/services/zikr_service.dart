import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// Цель по зикру: какой зикр и сколько раз в день.
class ZikrGoal {
  final String id;
  final String title;
  final String arabic;
  final int target;
  const ZikrGoal({
    required this.id,
    required this.title,
    this.arabic = '',
    required this.target,
  });

  ZikrGoal copyWith({int? target}) =>
      ZikrGoal(id: id, title: title, arabic: arabic, target: target ?? this.target);

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'arabic': arabic, 'target': target};

  factory ZikrGoal.fromJson(Map<String, dynamic> j) => ZikrGoal(
        id: j['id'] as String,
        title: j['title'] as String,
        arabic: j['arabic'] as String? ?? '',
        target: (j['target'] as num?)?.toInt() ?? 33,
      );
}

/// Счётчик зикров: настраиваемые дневные цели + счёт по дням
/// в SharedPreferences.
class ZikrService {
  static const _goalsKey = 'zikr_goals';
  static const _countPrefix = 'zikr_counts_';

  /// Тасбих Фатимы + истигфар — цели по умолчанию.
  static const defaultGoals = [
    ZikrGoal(
        id: 'subhanallah',
        title: 'СубханаЛлах',
        arabic: 'سُبْحَانَ ٱللَّٰهِ',
        target: 33),
    ZikrGoal(
        id: 'alhamdulillah',
        title: 'Альхамдулиллях',
        arabic: 'ٱلْحَمْدُ لِلَّٰهِ',
        target: 33),
    ZikrGoal(
        id: 'allahuakbar',
        title: 'Аллаху акбар',
        arabic: 'ٱللَّٰهُ أَكْبَرُ',
        target: 34),
    ZikrGoal(
        id: 'astaghfirullah',
        title: 'Астагфируллах',
        arabic: 'أَسْتَغْفِرُ ٱللَّٰهَ',
        target: 33),
  ];

  /// Каталог, из которого можно добавить готовый зикр в настройках.
  static const presets = [
    ZikrGoal(
        id: 'la_ilaha',
        title: 'Ля иляха илляЛлах',
        arabic: 'لَا إِلَٰهَ إِلَّا ٱللَّٰهُ',
        target: 100),
    ZikrGoal(
        id: 'salawat',
        title: 'Салават Пророку ﷺ',
        arabic: 'ٱللَّٰهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ',
        target: 100),
    ZikrGoal(
        id: 'hasbunallah',
        title: 'ХасбунаЛлах',
        arabic: 'حَسْبُنَا ٱللَّٰهُ وَنِعْمَ ٱلْوَكِيلُ',
        target: 33),
  ];

  final SharedPreferences _prefs;
  ZikrService(this._prefs);

  static Future<ZikrService> create() async =>
      ZikrService(await SharedPreferences.getInstance());

  List<ZikrGoal> get goals {
    final raw = _prefs.getString(_goalsKey);
    if (raw == null) return List.of(defaultGoals);
    try {
      return (jsonDecode(raw) as List)
          .map((e) => ZikrGoal.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return List.of(defaultGoals);
    }
  }

  Future<void> saveGoals(List<ZikrGoal> goals) => _prefs.setString(
      _goalsKey, jsonEncode(goals.map((g) => g.toJson()).toList()));

  String _dayKey(DateTime day) =>
      '$_countPrefix${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  Map<String, int> _readDay(DateTime day) {
    final raw = _prefs.getString(_dayKey(day));
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  int countOf(DateTime day, String id) => _readDay(day)[id] ?? 0;

  Future<void> increment(DateTime day, String id) async {
    final map = _readDay(day);
    map[id] = (map[id] ?? 0) + 1;
    await _prefs.setString(_dayKey(day), jsonEncode(map));
  }

  Future<void> reset(DateTime day, String id) async {
    final map = _readDay(day)..remove(id);
    await _prefs.setString(_dayKey(day), jsonEncode(map));
  }

  /// Коины за зикры за всю историю: каждые 33 повтора одного зикра = 1 коин.
  /// Засчитывается только в пределах дневной цели зикра, чтобы нельзя было
  /// «нафармить» коины бесконечными нажатиями сверх цели.
  int totalCoins() {
    final targets = {for (final g in goals) g.id: g.target};
    var coins = 0;
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_countPrefix)) continue;
      final raw = _prefs.getString(key);
      if (raw == null) continue;
      try {
        final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        for (final e in map.entries) {
          final count = (e.value as num).toInt();
          // Кап по дневной цели (по умолчанию 33, если цель неизвестна).
          final cap = targets[e.key] ?? 33;
          coins += math.min(count, cap) ~/ 33;
        }
      } catch (_) {}
    }
    return coins;
  }

  /// Доля выполнения дневных целей за день, 0..1.
  double dayCompletion(DateTime day) {
    final gs = goals;
    final totalTarget =
        gs.fold<int>(0, (s, g) => s + g.target);
    if (totalTarget == 0) return 0;
    final done = gs.fold<int>(
        0, (s, g) => s + math.min(countOf(day, g.id), g.target));
    return done / totalTarget;
  }

  bool allDone(DateTime day) =>
      goals.isNotEmpty &&
      goals.every((g) => countOf(day, g.id) >= g.target);

  /// Сколько дней подряд (заканчивая сегодня или вчера) выполнены все цели.
  int streak(DateTime now) {
    var day = DateTime(now.year, now.month, now.day);
    if (!allDone(day)) day = day.subtract(const Duration(days: 1));
    var n = 0;
    while (allDone(day)) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }
}
