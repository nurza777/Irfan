import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:shared_preferences/shared_preferences.dart';

import 'lang.dart';

/// Пол пользователя.
enum Gender {
  male('Мужской'),
  female('Женский');

  final String titleRu;
  const Gender(this.titleRu);
}

/// Приводит номер к виду +996XXXXXXXXX. Пустая строка — номер не распознан.
/// Логика повторяет серверную, чтобы приложение и реестр совпадали.
String normalizePhone(String v) {
  final raw = v.replaceAll(RegExp(r'[^0-9+]'), '');
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 9 || digits.length > 15) return '';
  if (raw.startsWith('+')) return '+$digits';
  if (digits.startsWith('0') && digits.length == 10) {
    return '+996${digits.substring(1)}';
  }
  if (digits.length == 9) return '+996$digits';
  return '+$digits';
}

/// Локальная учётная запись (хранится на устройстве; бэкенда пока нет).
class UserAccount {
  final String name;

  /// Номер телефона в виде +996XXXXXXXXX — он же опознаватель аккаунта.
  /// Почты в приложении больше нет: люди помнят номер, а не адрес, и код
  /// подтверждения всё равно идёт на телефон.
  final String phone;
  final String passHash;
  final DateTime createdAt;
  final int age;
  final Gender gender;
  final String city;
  const UserAccount({
    required this.name,
    required this.phone,
    required this.passHash,
    required this.createdAt,
    required this.age,
    required this.gender,
    this.city = '',
  });

  UserAccount copyWith(
          {int? age, Gender? gender, String? passHash, String? city}) =>
      UserAccount(
        name: name,
        phone: phone,
        passHash: passHash ?? this.passHash,
        createdAt: createdAt,
        age: age ?? this.age,
        gender: gender ?? this.gender,
        city: city ?? this.city,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'passHash': passHash,
        'createdAt': createdAt.toIso8601String(),
        'age': age,
        'gender': gender.name,
        'city': city,
      };

  factory UserAccount.fromJson(Map<String, dynamic> j) => UserAccount(
        name: j['name'] as String,
        // Аккаунты старых сборок опознавались почтой — переносим их на
        // телефон, если он был указан в анкете.
        phone: (j['phone'] as String?) ?? (j['email'] as String? ?? ''),
        passHash: j['passHash'] as String,
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ??
                DateTime.now(),
        age: (j['age'] as num?)?.toInt() ?? 0,
        gender: Gender.values.firstWhere(
            (g) => g.name == j['gender'],
            orElse: () => Gender.male),
        city: j['city'] as String? ?? '',
      );
}

/// Аргумент для расчёта PBKDF2 в фоновом изоляте (через `compute`).
class _Pbkdf2Req {
  final String password;
  final List<int> salt;
  final int iterations;
  const _Pbkdf2Req(this.password, this.salt, this.iterations);
}

/// PBKDF2-HMAC-SHA256, один 32-байтовый блок. Медленный намеренно — чтобы
/// перебор украденного хеша был дорогим. Считается в изоляте, не блокируя UI.
List<int> _pbkdf2Sync(_Pbkdf2Req r) {
  final hmac = Hmac(sha256, utf8.encode(r.password));
  // salt || INT32BE(1)
  final block = <int>[...r.salt, 0, 0, 0, 1];
  var u = hmac.convert(block).bytes;
  final result = List<int>.of(u);
  for (var i = 1; i < r.iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return result;
}

/// Регистрация и вход. Пароли не хранятся в открытом виде: PBKDF2-HMAC-SHA256
/// со случайной солью и 120 000 итераций (формат `pbkdf2$итер$сольHex$хешHex`).
/// Старые аккаунты (несолёный SHA-256) при первом входе прозрачно
/// пересохраняются в новом формате.
class AuthService {
  static const _usersKey = 'auth_users';
  static const _currentKey = 'auth_current';

  final SharedPreferences _prefs;
  AuthService(this._prefs);

  static Future<AuthService> create() async =>
      AuthService(await SharedPreferences.getInstance());

  List<UserAccount> _users() {
    final raw = _prefs.getString(_usersKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => UserAccount.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveUsers(List<UserAccount> users) => _prefs.setString(
      _usersKey, jsonEncode(users.map((u) => u.toJson()).toList()));

  /// Текущий вошедший пользователь, либо null.
  UserAccount? get current {
    final phone = _prefs.getString(_currentKey);
    if (phone == null) return null;
    return _users().where((u) => u.phone == phone).firstOrNull;
  }

  static const _iterations = 120000;

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _unhex(String s) {
    final out = <int>[];
    for (var i = 0; i + 1 < s.length; i += 2) {
      out.add(int.parse(s.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  /// Сравнение строк за постоянное время (без утечки по таймингу).
  static bool _constEq(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Новый хеш пароля: `pbkdf2$итер$сольHex$хешHex` со случайной солью.
  Future<String> _newHash(String password) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final dk =
        await compute(_pbkdf2Sync, _Pbkdf2Req(password, salt, _iterations));
    return 'pbkdf2\$$_iterations\$${_hex(salt)}\$${_hex(dk)}';
  }

  /// Проверка пароля против сохранённого хеша.
  /// `ok` — совпал; `needsUpgrade` — старый формат, надо пересохранить.
  Future<({bool ok, bool needsUpgrade})> _verify(
      String login, String password, String stored) async {
    if (stored.startsWith('pbkdf2\$')) {
      final parts = stored.split('\$'); // pbkdf2, iter, saltHex, hashHex
      if (parts.length != 4) return (ok: false, needsUpgrade: false);
      final iter = int.tryParse(parts[1]) ?? 0;
      if (iter <= 0) return (ok: false, needsUpgrade: false);
      final dk = await compute(
          _pbkdf2Sync, _Pbkdf2Req(password, _unhex(parts[2]), iter));
      return (ok: _constEq(_hex(dk), parts[3]), needsUpgrade: false);
    }
    // Legacy: несолёный SHA-256 от `логин:пароль`.
    final legacy =
        sha256.convert(utf8.encode('$login:$password')).toString();
    return (ok: _constEq(legacy, stored), needsUpgrade: true);
  }

  /// null — успех (и сразу вход), иначе текст ошибки.
  Future<String?> register({
    required String name,
    required String phone,
    required String password,
    required int age,
    required Gender? gender,
    String city = '',
  }) async {
    if (name.trim().isEmpty) return t('Введите имя');
    final ph = normalizePhone(phone);
    if (ph.isEmpty) return t('Некорректный номер телефона');
    if (password.length < 6) return t('Пароль — минимум 6 символов');
    if (age < 5 || age > 120) return t('Укажите корректный возраст (5–120)');
    if (gender == null) return t('Выберите пол');
    final users = _users();
    if (users.any((u) => u.phone == ph)) {
      return t('Аккаунт с таким номером уже есть');
    }
    users.add(UserAccount(
      name: name.trim(),
      phone: ph,
      passHash: await _newHash(password),
      createdAt: DateTime.now(),
      age: age,
      gender: gender,
      city: city.trim(),
    ));
    await _saveUsers(users);
    await _prefs.setString(_currentKey, ph);
    return null;
  }

  /// Обновляет возраст/пол текущего пользователя.
  Future<void> updateCurrentProfile({int? age, Gender? gender}) async {
    final phone = _prefs.getString(_currentKey);
    if (phone == null) return;
    final users = _users();
    final i = users.indexWhere((u) => u.phone == phone);
    if (i < 0) return;
    users[i] = users[i].copyWith(age: age, gender: gender);
    await _saveUsers(users);
  }

  /// null — успех, иначе текст ошибки.
  Future<String?> login(
      {required String phone, required String password}) async {
    // Аккаунты старых сборок опознавались почтой. Чтобы люди не потеряли
    // свою статистику, пускаем и по ней: если введённое не похоже на номер,
    // ищем совпадение как есть.
    final raw = phone.trim().toLowerCase();
    final ph = normalizePhone(phone);
    final key = ph.isEmpty ? raw : ph;
    if (key.isEmpty) return t('Некорректный номер телефона');
    final user = _users().where((u) => u.phone == key).firstOrNull;
    if (user == null) return t('Аккаунт не найден');
    final res = await _verify(key, password, user.passHash);
    if (!res.ok) return t('Неверный пароль');
    // Прозрачно переводим старый несолёный SHA-256 на PBKDF2.
    if (res.needsUpgrade) {
      final users = _users();
      final i = users.indexWhere((u) => u.phone == key);
      if (i >= 0) {
        users[i] = users[i].copyWith(passHash: await _newHash(password));
        await _saveUsers(users);
      }
    }
    await _prefs.setString(_currentKey, ph);
    return null;
  }

  Future<void> logout() => _prefs.remove(_currentKey);
}
