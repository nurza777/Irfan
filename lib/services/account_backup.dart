import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'device_key.dart';

/// Перенос аккаунта на другой телефон.
///
/// Аккаунт ученика живёт на устройстве: пароля на сервере нет, а вся история —
/// трекер намазов, счётчики зикров, обеты, закладки и заметки Корана — лежит в
/// SharedPreferences. До этого класса смена телефона (или просто утопленный
/// телефон) означала потерю серии, коинов и всей истории без всякой
/// возможности вернуть их.
///
/// Устроено просто: приложение шлёт на сервер слепок своего хранилища, а на
/// новом телефоне забирает его обратно, доказав, что номер его. Сервер в
/// содержимое слепка не смотрит и ничего по нему не считает — заработанное
/// по-прежнему считается по полям реестра со своими потолками, так что
/// подложным слепком коинов себе не прибавить.
class AccountBackup {
  const AccountBackup._();

  // ── Что переносится ────────────────────────────────────────────────────
  //
  // Список явный, а не «всё подряд, кроме…»: в хранилище со временем заводятся
  // новые ключи, и молчаливая отправка на сервер чего попало — ровно тот
  // случай, когда однажды туда уедет то, чему там не место.

  /// Ключи по префиксу: запись на каждый день или на каждый урок.
  static const _prefixes = [
    'tracker_',             // отметки намазов по дням — главное, ради чего всё
    'zikr_counts_',         // счётчики зикров по дням
    'private_zikr_done_',   // выполнение закрытых обетов по дням
    'lesson_at_',           // место остановки в уроке
    'settings_',            // город, мазхаб, метод расчёта, напоминания, язык
  ];

  /// Ключи целиком.
  static const _keys = [
    'zikr_goals',
    'private_zikrs',
    'coins_spent',
    'coins_redemptions',
    'quran_bookmarks',
    'quran_notes',
    'quran_font',
    'quran_font_family',
    'quran_mode',
    'quran_reciter',
    'quran_show_arabic',
    'quran_show_translation',
    'quran_tajwid',
    'quran_translation',
  ];

  // Намеренно НЕ переносится:
  //   auth_users            — хеши паролей; на сервер они не уходили никогда,
  //                           и заводить для этого исключение не будем: на
  //                           новом телефоне человек задаёт пароль заново;
  //   auth_current          — кто сейчас вошёл, дело этого устройства;
  //   irfan_staff_token,
  //   staff_session         — вход устаза, живёт в Keychain и своей жизнью;
  //   wallpaper_path        — путь к файлу НА ЭТОМ устройстве; на другом он
  //                           указывал бы в пустоту, и фон бы пропал;
  //   api_base_url,
  //   live_base_url         — адрес сервера, отладочная настройка устройства;
  //   onboarding_done       — приветствие новому телефону показать не грех;
  //   chat_blocked_authors  — там чужие имена, а на сервер уезжает только
  //                           своё;
  //   backup_*              — служебные метки самого переноса.

  static bool covers(String key) =>
      _keys.contains(key) || _prefixes.any(key.startsWith);

  // Метки последней отправки. Под _prefixes/_keys не подпадают — то есть в
  // сам слепок не попадают и не делают его каждый раз новым.
  static const _hashKey = 'backup_hash';
  static const _atKey = 'backup_at';

  /// Не чаще раза в четверть часа — и то лишь если что-то изменилось.
  static const _minInterval = Duration(minutes: 15);

  /// Раз в сутки слепок уходит даже без изменений: так видно, что телефон
  /// ещё жив, а если прошлая отправка не долетела — доедет эта.
  static const _maxInterval = Duration(days: 1);

  // ── Слепок ─────────────────────────────────────────────────────────────

  /// Собирает слепок хранилища. Значения разложены по типам: SharedPreferences
  /// строго типизированы, и вернуть строку туда, где был `int`, значит уронить
  /// чтение на новом телефоне.
  static Map<String, dynamic> collect(SharedPreferences p) {
    final s = <String, String>{};
    final i = <String, int>{};
    final b = <String, bool>{};
    final d = <String, double>{};
    final l = <String, List<String>>{};
    for (final k in p.getKeys()) {
      if (!covers(k)) continue;
      final v = p.get(k);
      if (v is String) {
        s[k] = v;
      } else if (v is bool) {
        // bool ДО int: в Dart это разные типы, но порядок здесь важен для
        // читателя — `is int` на bool не сработает, а обратная ошибка частая.
        b[k] = v;
      } else if (v is int) {
        i[k] = v;
      } else if (v is double) {
        d[k] = v;
      } else if (v is List<String>) {
        l[k] = v;
      }
    }
    return {'v': 1, 's': s, 'i': i, 'b': b, 'd': d, 'l': l};
  }

  /// Кладёт слепок в хранилище.
  ///
  /// Правило одно: **уже существующий ключ не трогаем**. Человек мог
  /// попользоваться новым телефоном до того, как вспомнил про перенос, — и его
  /// намазы за эти дни важнее старой записи за тот же день. Исключения — два
  /// денежных ключа, где «не трогать» означало бы вернуть в кошелёк уже
  /// потраченное (см. ниже).
  ///
  /// [serverSpent] — сколько, по данным сервера, потрачено коинов. Это
  /// источник истины: слепок мог быть снят до выкупа награды.
  static Future<int> apply(
    SharedPreferences p,
    Map<String, dynamic> snap, {
    int serverSpent = 0,
  }) async {
    var written = 0;

    Future<void> put(String k, Future<void> Function() write) async {
      if (p.containsKey(k)) return;
      await write();
      written++;
    }

    Map<String, dynamic> part(String name) {
      final v = snap[name];
      return v is Map ? Map<String, dynamic>.from(v) : const {};
    }

    for (final e in part('s').entries) {
      if (!covers(e.key) || e.value is! String) continue;
      if (e.key == 'coins_redemptions') continue; // сливается ниже
      await put(e.key, () => p.setString(e.key, e.value as String));
    }
    for (final e in part('i').entries) {
      if (!covers(e.key) || e.value is! int) continue;
      if (e.key == 'coins_spent') continue; // берётся максимум, см. ниже
      await put(e.key, () => p.setInt(e.key, e.value as int));
    }
    for (final e in part('b').entries) {
      if (!covers(e.key) || e.value is! bool) continue;
      await put(e.key, () => p.setBool(e.key, e.value as bool));
    }
    for (final e in part('d').entries) {
      if (!covers(e.key) || e.value is! num) continue;
      await put(e.key, () => p.setDouble(e.key, (e.value as num).toDouble()));
    }
    for (final e in part('l').entries) {
      if (!covers(e.key) || e.value is! List) continue;
      final list = (e.value as List).whereType<String>().toList();
      await put(e.key, () => p.setStringList(e.key, list));
    }

    // Потраченное: наибольшее из трёх. Меньшее число вернуло бы человеку
    // коины, которые он уже обменял на чётки.
    final spent = [
      p.getInt('coins_spent') ?? 0,
      (part('i')['coins_spent'] as num?)?.toInt() ?? 0,
      serverSpent,
    ].reduce((a, b) => a > b ? a : b);
    if (spent != (p.getInt('coins_spent') ?? 0)) {
      await p.setInt('coins_spent', spent);
      written++;
    }

    // История выкупов — объединение по коду: списки с двух телефонов
    // дополняют друг друга, а не затирают.
    final merged = _mergeRedemptions(
        p.getString('coins_redemptions'), part('s')['coins_redemptions']);
    if (merged != null) {
      await p.setString('coins_redemptions', merged);
      written++;
    }
    return written;
  }

  /// Объединяет два JSON-списка выкупов по полю `code`. null — сливать нечего.
  static String? _mergeRedemptions(String? mine, Object? theirs) {
    if (theirs is! String || theirs.isEmpty) return null;
    List<dynamic> parse(String? raw) {
      if (raw == null || raw.isEmpty) return const [];
      try {
        final v = jsonDecode(raw);
        return v is List ? v : const [];
      } catch (_) {
        return const [];
      }
    }

    final out = <String, dynamic>{};
    for (final e in [...parse(theirs), ...parse(mine)]) {
      if (e is! Map) continue;
      final code = (e['code'] ?? '').toString();
      // Без кода запись не с чем сличать — держим по её же содержимому.
      out.putIfAbsent(code.isEmpty ? jsonEncode(e) : code, () => e);
    }
    if (out.isEmpty) return null;
    return jsonEncode(out.values.toList());
  }

  // ── Отправка ───────────────────────────────────────────────────────────

  /// Идёт ли отправка прямо сейчас. Позвать могут почти одновременно — на
  /// отметке намаза и из отложенного отчёта при запуске, — и без этого флага
  /// оба вызова проходят проверку срока раньше, чем первый успеет её
  /// записать, то есть один и тот же слепок уезжает дважды.
  static bool _busy = false;

  /// Отправляет слепок, если он изменился (или сутки прошли).
  /// Возвращает true, если сервер принял.
  static Future<bool> maybeUpload(String phone) async {
    if (phone.isEmpty || _busy) return false;
    final p = await SharedPreferences.getInstance();
    // Срок проверяется ДО сборки слепка: метод зовут в том числе на каждую
    // отметку намаза, а сборка — это обход всего хранилища.
    final at = p.getInt(_atKey) ?? 0;
    final since = DateTime.now().millisecondsSinceEpoch - at;
    if (since < _minInterval.inMilliseconds) return false;
    final snap = collect(p);
    final hash = sha256.convert(utf8.encode(jsonEncode(snap))).toString();
    if (p.getString(_hashKey) == hash &&
        since < _maxInterval.inMilliseconds) {
      return false;
    }

    _busy = true;
    try {
      final ok = await _upload(phone, snap);
      if (ok) {
        await p.setString(_hashKey, hash);
        await p.setInt(_atKey, DateTime.now().millisecondsSinceEpoch);
      }
      return ok;
    } finally {
      _busy = false;
    }
  }

  static Future<bool> _upload(String phone, Map<String, dynamic> snap) async {
    try {
      final base = await ApiConfig.base();
      final secret = await DeviceKey.get();
      final r = await http
          .post(
            Uri.parse('$base/backup'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: utf8.encode(jsonEncode({
              'phone': phone,
              if (secret.isNotEmpty) 'secret': secret,
              'data': snap,
            })),
          )
          .timeout(const Duration(seconds: 10));
      return r.statusCode == 201;
    } catch (e) {
      debugPrint('backup upload error: $e');
      return false;
    }
  }

  /// Забывает метки отправки — чтобы следующий слепок ушёл сразу.
  /// Нужно после восстановления: хранилище стало другим, а метка осталась бы
  /// от прежнего аккаунта.
  static Future<void> forgetMarks() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_hashKey);
    await p.remove(_atKey);
  }
}

/// Чем закончилась попытка восстановления.
enum RestoreStatus {
  ok,

  /// Такого номера в реестре нет.
  notFound,

  /// Ни ключа устройства, ни действующего разрешения — нужен код.
  needsCode,

  /// Аккаунт заблокирован администратором.
  blocked,
  offline,
  error,
}

/// Ответ сервера на восстановление.
class RestoreResult {
  final RestoreStatus status;
  final String name;
  final String gender;
  final int age;
  final String city;

  /// Когда аккаунт был создан в приложении. Сохраняем как есть: от этой даты
  /// сервер считает потолок «сколько намазов физически можно было прочитать».
  final DateTime? createdAt;

  /// Сколько коинов, по данным сервера, уже потрачено.
  final int spent;

  /// Слепок хранилища. null — аккаунт есть, а слепка нет (человек не успел
  /// обновиться до сборки с переносом).
  final Map<String, dynamic>? data;
  final DateTime? updatedAt;

  const RestoreResult(
    this.status, {
    this.name = '',
    this.gender = '',
    this.age = 0,
    this.city = '',
    this.createdAt,
    this.spent = 0,
    this.data,
    this.updatedAt,
  });

  bool get isOk => status == RestoreStatus.ok;

  /// Есть ли что переносить, кроме анкеты.
  bool get hasData => data != null && data!.isNotEmpty;
}

/// Запрос на перенос аккаунта.
class AccountRestore {
  const AccountRestore._();

  /// [ticket] — разрешение, выданное сервером после верного кода. Без него
  /// сервер пустит, только если этот телефон уже закреплён за записью
  /// (переустановка приложения: Keychain её переживает, а хранилище — нет).
  static Future<RestoreResult> fetch(String phone, {String? ticket}) async {
    final int status;
    final Map<String, dynamic> j;
    try {
      final base = await ApiConfig.base();
      final secret = await DeviceKey.get();
      final r = await http
          .post(
            Uri.parse('$base/account/restore'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: utf8.encode(jsonEncode({
              'phone': phone,
              if (secret.isNotEmpty) 'secret': secret,
              if (ticket != null && ticket.isNotEmpty) 'ticket': ticket,
            })),
          )
          .timeout(const Duration(seconds: 15));
      status = r.statusCode;
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      j = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (e) {
      debugPrint('restore error: $e');
      return const RestoreResult(RestoreStatus.offline);
    }
    if (status == 404) return const RestoreResult(RestoreStatus.notFound);
    if (status == 403) {
      return RestoreResult(j['error'] == 'blocked'
          ? RestoreStatus.blocked
          : RestoreStatus.needsCode);
    }
    if (status != 200) return const RestoreResult(RestoreStatus.error);

    final profile = j['profile'] is Map
        ? Map<String, dynamic>.from(j['profile'] as Map)
        : <String, dynamic>{};
    final created = (profile['accountCreatedAt'] as num?)?.toInt();
    final updated = (j['updatedAt'] as num?)?.toInt();
    return RestoreResult(
      RestoreStatus.ok,
      name: (profile['name'] as String?) ?? '',
      gender: (profile['gender'] as String?) ?? '',
      age: (profile['age'] as num?)?.toInt() ?? 0,
      city: (profile['city'] as String?) ?? '',
      createdAt: created == null || created <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(created),
      spent: (j['spent'] as num?)?.toInt() ?? 0,
      data: j['data'] is Map
          ? Map<String, dynamic>.from(j['data'] as Map)
          : null,
      updatedAt: updated == null || updated <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(updated),
    );
  }
}
