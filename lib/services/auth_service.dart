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
  final String email;
  final String passHash;
  final DateTime createdAt;
  final int age;
  final Gender gender;
  final String phone;
  final String city;
  const UserAccount({
    required this.name,
    required this.email,
    required this.passHash,
    required this.createdAt,
    required this.age,
    required this.gender,
    this.phone = '',
    this.city = '',
  });

  UserAccount copyWith(
          {int? age,
          Gender? gender,
          String? passHash,
          String? phone,
          String? city}) =>
      UserAccount(
        name: name,
        email: email,
        passHash: passHash ?? this.passHash,
        createdAt: createdAt,
        age: age ?? this.age,
        gender: gender ?? this.gender,
        phone: phone ?? this.phone,
        city: city ?? this.city,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'passHash': passHash,
        'createdAt': createdAt.toIso8601String(),
        'age': age,
        'gender': gender.name,
        'phone': phone,
        'city': city,
      };

  factory UserAccount.fromJson(Map<String, dynamic> j) => UserAccount(
        name: j['name'] as String,
        email: j['email'] as String,
        passHash: j['passHash'] as String,
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ??
                DateTime.now(),
        age: (j['age'] as num?)?.toInt() ?? 0,
        gender: Gender.values.firstWhere(
            (g) => g.name == j['gender'],
            orElse: () => Gender.male),
        phone: j['phone'] as String? ?? '',
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
    final email = _prefs.getString(_currentKey);
    if (email == null) return null;
    return _users().where((u) => u.email == email).firstOrNull;
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
      String email, String password, String stored) async {
    if (stored.startsWith('pbkdf2\$')) {
      final parts = stored.split('\$'); // pbkdf2, iter, saltHex, hashHex
      if (parts.length != 4) return (ok: false, needsUpgrade: false);
      final iter = int.tryParse(parts[1]) ?? 0;
      if (iter <= 0) return (ok: false, needsUpgrade: false);
      final dk = await compute(
          _pbkdf2Sync, _Pbkdf2Req(password, _unhex(parts[2]), iter));
      return (ok: _constEq(_hex(dk), parts[3]), needsUpgrade: false);
    }
    // Legacy: несолёный SHA-256 от `email:пароль`.
    final legacy =
        sha256.convert(utf8.encode('$email:$password')).toString();
    return (ok: _constEq(legacy, stored), needsUpgrade: true);
  }

  static final _emailRe = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  /// null — успех (и сразу вход), иначе текст ошибки.
  Future<String?> register({
    required String name,
    required String email,
    required String password,
    required int age,
    required Gender? gender,
    String phone = '',
    String city = '',
  }) async {
    final e = email.trim().toLowerCase();
    if (name.trim().isEmpty) return t('Введите имя');
    if (!_emailRe.hasMatch(e)) return t('Некорректный email');
    if (password.length < 6) return t('Пароль — минимум 6 символов');
    if (age < 5 || age > 120) return t('Укажите корректный возраст (5–120)');
    if (gender == null) return t('Выберите пол');
    // Телефон нужен, чтобы прислать код подтверждения.
    final ph = normalizePhone(phone);
    if (ph.isEmpty) return t('Укажите номер телефона');
    final users = _users();
    if (users.any((u) => u.email == e)) {
      return t('Аккаунт с таким email уже есть');
    }
    users.add(UserAccount(
      name: name.trim(),
      email: e,
      passHash: await _newHash(password),
      createdAt: DateTime.now(),
      age: age,
      gender: gender,
      phone: ph,
      city: city.trim(),
    ));
    await _saveUsers(users);
    await _prefs.setString(_currentKey, e);
    return null;
  }

  /// Обновляет возраст/пол текущего пользователя.
  Future<void> updateCurrentProfile({int? age, Gender? gender}) async {
    final email = _prefs.getString(_currentKey);
    if (email == null) return;
    final users = _users();
    final i = users.indexWhere((u) => u.email == email);
    if (i < 0) return;
    users[i] = users[i].copyWith(age: age, gender: gender);
    await _saveUsers(users);
  }

  /// null — успех, иначе текст ошибки.
  Future<String?> login(
      {required String email, required String password}) async {
    final e = email.trim().toLowerCase();
    final user = _users().where((u) => u.email == e).firstOrNull;
    if (user == null) return t('Аккаунт не найден');
    final res = await _verify(e, password, user.passHash);
    if (!res.ok) return t('Неверный пароль');
    // Прозрачно переводим старый несолёный SHA-256 на PBKDF2.
    if (res.needsUpgrade) {
      final users = _users();
      final i = users.indexWhere((u) => u.email == e);
      if (i >= 0) {
        users[i] = users[i].copyWith(passHash: await _newHash(password));
        await _saveUsers(users);
      }
    }
    await _prefs.setString(_currentKey, e);
    return null;
  }

  Future<void> logout() => _prefs.remove(_currentKey);
}
