/// Закрытые зикры — личные обеты, которые человек ставит себе сам.
///
/// Отличие от обычных: здесь не счётчик по одному нажатию, а план на день,
/// который закрывают частями. Прочитал сколько-то — вписал число, оно ушло
/// из остатка. Пока остаток не обнулился, зикр считается незакрытым.
///
/// Напоминания можно поставить на несколько моментов дня: скажем, 200 раз
/// суммарно, но подходить к этому утром, днём и вечером.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Время напоминания в течение дня.
class ZikrReminder {
  final int hour;
  final int minute;
  const ZikrReminder(this.hour, this.minute);

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {'h': hour, 'm': minute};

  factory ZikrReminder.fromJson(Map<String, dynamic> j) => ZikrReminder(
        (j['h'] as num?)?.toInt() ?? 0,
        (j['m'] as num?)?.toInt() ?? 0,
      );
}

class PrivateZikr {
  final String id;
  final String title;

  /// Сколько нужно прочитать за день.
  final int target;
  final List<ZikrReminder> reminders;
  final DateTime createdAt;

  const PrivateZikr({
    required this.id,
    required this.title,
    required this.target,
    required this.reminders,
    required this.createdAt,
  });

  PrivateZikr copyWith(
          {String? title, int? target, List<ZikrReminder>? reminders}) =>
      PrivateZikr(
        id: id,
        title: title ?? this.title,
        target: target ?? this.target,
        reminders: reminders ?? this.reminders,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'target': target,
        'reminders': reminders.map((r) => r.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory PrivateZikr.fromJson(Map<String, dynamic> j) => PrivateZikr(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        target: (j['target'] as num?)?.toInt() ?? 1,
        reminders: ((j['reminders'] as List?) ?? [])
            .map((e) => ZikrReminder.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class PrivateZikrService extends ChangeNotifier {
  static const _listKey = 'private_zikrs';
  static const _donePrefix = 'private_zikr_done_';  // + дата + id

  final SharedPreferences _prefs;
  PrivateZikrService(this._prefs);

  static Future<PrivateZikrService> create() async =>
      PrivateZikrService(await SharedPreferences.getInstance());

  List<PrivateZikr> get all {
    final raw = _prefs.getString(_listKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => PrivateZikr.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<PrivateZikr> list) async {
    await _prefs.setString(
        _listKey, jsonEncode(list.map((z) => z.toJson()).toList()));
    notifyListeners();
  }

  Future<PrivateZikr> add({
    required String title,
    required int target,
    required List<ZikrReminder> reminders,
  }) async {
    final z = PrivateZikr(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.trim(),
      target: target.clamp(1, 100000),
      reminders: reminders,
      createdAt: DateTime.now(),
    );
    await _save([...all, z]);
    return z;
  }

  Future<void> update(PrivateZikr z) async {
    final list = all.map((x) => x.id == z.id ? z : x).toList();
    await _save(list);
  }

  Future<void> remove(String id) async {
    await _save(all.where((z) => z.id != id).toList());
    // Историю выполнения тоже чистим, чтобы не копилась зря.
    for (final k in _prefs.getKeys().toList()) {
      if (k.startsWith(_donePrefix) && k.endsWith('_$id')) {
        await _prefs.remove(k);
      }
    }
  }

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Сколько прочитано сегодня.
  int doneToday(DateTime day, String id) =>
      _prefs.getInt('$_donePrefix${dayKey(day)}_$id') ?? 0;

  /// Остаток на сегодня.
  int leftToday(DateTime day, PrivateZikr z) =>
      (z.target - doneToday(day, z.id)).clamp(0, z.target);

  bool isClosedToday(DateTime day, PrivateZikr z) => leftToday(day, z) == 0;

  /// Записывает прочитанное. Возвращает новый остаток.
  Future<int> addProgress(DateTime day, PrivateZikr z, int count) async {
    if (count <= 0) return leftToday(day, z);
    final key = '$_donePrefix${dayKey(day)}_${z.id}';
    // Больше цели не записываем: остаток не должен уходить в минус.
    final next = (doneToday(day, z.id) + count).clamp(0, z.target);
    await _prefs.setInt(key, next);
    notifyListeners();
    return (z.target - next).clamp(0, z.target);
  }

  /// Обнуляет сегодняшний прогресс (если вписали лишнее).
  Future<void> resetToday(DateTime day, PrivateZikr z) async {
    await _prefs.remove('$_donePrefix${dayKey(day)}_${z.id}');
    notifyListeners();
  }

  /// Сколько закрыто полностью за сегодня — для сводки.
  int closedCount(DateTime day) =>
      all.where((z) => isClosedToday(day, z)).length;
}
