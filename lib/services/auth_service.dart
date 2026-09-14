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

  /// Дата рождения. Возраст из неё считается сам — см. [age].
  ///
  /// Раньше человек вводил возраст числом, и оно застывало навсегда: анкета
  /// говорила «25» и через три года. Дата не устаревает.
  ///
  /// null — у записей, заведённых прежними сборками: там сохранено только
  /// число. Их не трогаем, возраст берём как есть.
  final DateTime? birthDate;

  /// Возраст, введённый числом в старых сборках. Читать надо [age].
  final int storedAge;

  /// Пол — НЕОБЯЗАТЕЛЕН, поэтому допускает null.
  ///
  /// Раньше без него нельзя было зарегистрироваться, и App Store вернул
  /// приложение по правилу 5.1.1(v): требовать личные данные можно только
  /// те, без которых приложение не работает. Пол здесь нужен ровно для
  /// одного — согласования окончаний в поздравлениях и на бланке диплома
  /// («прошёл» / «прошла»). Не указан — пишем в мужском роде, как принято
  /// в русском языке при неизвестном адресате.
  final Gender? gender;
  final String city;

  /// Доказательство пароля для сервера — см. [AuthService.makeProof].
  ///
  /// [passHash] для этого не годится: у него своя случайная соль на каждом
  /// телефоне, и с другого устройства такое же значение не получить. А вход
  /// по номеру и паролю нужен именно с ДРУГОГО телефона.
  ///
  /// Пустая строка — у записей, заведённых прежними сборками: там пароль
  /// только местный. Значение появится при первом же входе.
  final String serverProof;
  const UserAccount({
    required this.name,
    required this.phone,
    required this.passHash,
    required this.createdAt,
    required this.storedAge,
    this.birthDate,
    required this.gender,
    this.city = '',
    this.serverProof = '',
  });

  /// Полных лет. Считается от даты рождения, если она есть.
  int get age {
    final b = birthDate;
    if (b == null) return storedAge;
    final now = DateTime.now();
    var years = now.year - b.year;
    // День рождения в этом году ещё не наступил — год не засчитан.
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) {
      years--;
    }
    return years < 0 ? 0 : years;
  }

  UserAccount copyWith(
          {int? storedAge,
          DateTime? birthDate,
          Gender? gender,
          String? passHash,
          String? city,
          String? serverProof}) =>
      UserAccount(
        name: name,
        phone: phone,
        passHash: passHash ?? this.passHash,
        createdAt: createdAt,
        storedAge: storedAge ?? this.storedAge,
        birthDate: birthDate ?? this.birthDate,
        gender: gender ?? this.gender,
        city: city ?? this.city,
        serverProof: serverProof ?? this.serverProof,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'passHash': passHash,
        'createdAt': createdAt.toIso8601String(),
        // Пишем ВЫЧИСЛЕННЫЙ возраст, а не хранимый: он уходит на сервер и
        // в панель, где должен быть сегодняшним. А рядом — саму дату, из
        // которой он и берётся при следующем чтении.
        'age': age,
        if (birthDate != null)
          'birthDate': birthDate!.toIso8601String().substring(0, 10),
        'gender': gender?.name ?? '',
        'city': city,
        if (serverProof.isNotEmpty) 'serverProof': serverProof,
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
        storedAge: (j['age'] as num?)?.toInt() ?? 0,
        birthDate: DateTime.tryParse((j['birthDate'] as String?) ?? ''),
        gender: Gender.values
            .where((g) => g.name == j['gender'])
            .cast<Gender?>()
            .firstOrNull,
        city: j['city'] as String? ?? '',
        serverProof: j['serverProof'] as String? ?? '',
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

  /// Доказательство пароля для сервера: одно и то же значение на любом
  /// телефоне, потому что соль берётся из номера, а не случайная.
  ///
  /// Нужно, чтобы человек входил в свой аккаунт с НОВОГО телефона просто по
  /// номеру и паролю. Сервер сравнивает это значение с тем, что у него
  /// записано, — и пускает. Раньше вместо этого спрашивали код, который
  /// называл устаз вручную.
  ///
  /// Сам пароль серверу не уходит: там оседает только PBKDF2 поверх этого
  /// значения (см. `_upsert_user` в apiserver.py). То есть пароль в открытом
  /// виде не знает ни сеть, ни файл реестра.
  static Future<String> makeProof(String phone, String password) async {
    final key = normalizePhone(phone);
    if (key.isEmpty || password.isEmpty) return '';
    // Соль выводим из номера: она обязана совпадать на всех устройствах, но
    // не должна быть общей для всех аккаунтов — иначе одна радужная таблица
    // вскрыла бы весь реестр разом.
    final salt = sha256.convert(utf8.encode('irfan-acc:$key')).bytes
        .sublist(0, 16);
    final dk =
        await compute(_pbkdf2Sync, _Pbkdf2Req(password, salt, _iterations));
    return _hex(dk);
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
    required DateTime? birthDate,
    required Gender? gender,
    String city = '',
  }) async {
    if (name.trim().isEmpty) return t('Введите имя');
    final ph = normalizePhone(phone);
    if (ph.isEmpty) return t('Некорректный номер телефона');
    if (password.length < 6) return t('Пароль — минимум 6 символов');
    if (birthDate == null) return t('Укажите дату рождения');
    // Возраст считаем из даты и проверяем его же — потолок нужен не ради
    // придирки: дата из будущего или 1900 года означает промах в выборе,
    // а не столетнего ученика.
    final years = _yearsSince(birthDate);
    if (years < 5 || years > 120) {
      return t('Проверьте дату рождения');
    }
    // Пол не проверяем: он необязателен (см. UserAccount.gender).
    final users = _users();
    if (users.any((u) => u.phone == ph)) {
      return t('Аккаунт с таким номером уже есть');
    }
    users.add(UserAccount(
      name: name.trim(),
      phone: ph,
      passHash: await _newHash(password),
      createdAt: DateTime.now(),
      storedAge: years,
      birthDate: birthDate,
      gender: gender,
      city: city.trim(),
      serverProof: await makeProof(ph, password),
    ));
    await _saveUsers(users);
    await _prefs.setString(_currentKey, ph);
    return null;
  }

  /// Заводит локальный аккаунт по анкете, восстановленной с сервера, и сразу
  /// входит в него. null — успех, иначе текст ошибки.
  ///
  /// От [register] отличается двумя вещами. Во-первых, [createdAt] берётся с
  /// сервера, а не ставится «сейчас»: от даты создания аккаунта считается
  /// потолок «сколько намазов физически можно было прочитать», и новая дата
  /// обрезала бы человеку его же историю. Во-вторых, запись с таким номером
  /// не считается помехой — она перезаписывается: сюда попадают ровно тогда,
  /// когда аккаунт переносят на это устройство.
  Future<String?> restore({
    required String name,
    required String phone,
    required String password,
    required DateTime createdAt,
    int age = 0,
    DateTime? birthDate,
    Gender? gender,
    String city = '',
  }) async {
    final ph = normalizePhone(phone);
    if (ph.isEmpty) return t('Некорректный номер телефона');
    if (password.length < 6) return t('Пароль — минимум 6 символов');
    final users = _users()..removeWhere((u) => u.phone == ph);
    users.add(UserAccount(
      name: name.trim().isEmpty ? ph : name.trim(),
      phone: ph,
      passHash: await _newHash(password),
      createdAt: createdAt,
      storedAge: age,
      birthDate: birthDate,
      gender: gender,
      city: city.trim(),
      serverProof: await makeProof(ph, password),
    ));
    await _saveUsers(users);
    await _prefs.setString(_currentKey, ph);
    return null;
  }

  /// Полных лет от даты рождения до сегодня.
  static int _yearsSince(DateTime b) {
    final now = DateTime.now();
    var years = now.year - b.year;
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) {
      years--;
    }
    return years;
  }

  /// Обновляет дату рождения и пол текущего пользователя.
  Future<void> updateCurrentProfile(
      {DateTime? birthDate, Gender? gender}) async {
    final phone = _prefs.getString(_currentKey);
    if (phone == null) return;
    final users = _users();
    final i = users.indexWhere((u) => u.phone == phone);
    if (i < 0) return;
    users[i] = users[i].copyWith(
        birthDate: birthDate,
        storedAge: birthDate == null ? null : _yearsSince(birthDate),
        gender: gender);
    await _saveUsers(users);
  }

  /// Заведён ли аккаунт с этим номером НА ЭТОМ телефоне.
  ///
  /// По этому признаку вход решает, проверять ли пароль у себя или идти за
  /// аккаунтом на сервер: человек мог сменить телефон.
  bool hasLocal(String phone) {
    final raw = phone.trim().toLowerCase();
    final ph = normalizePhone(phone);
    final key = ph.isEmpty ? raw : ph;
    if (key.isEmpty) return false;
    return _users().any((u) => u.phone == key);
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
    // Прозрачно переводим старый несолёный SHA-256 на PBKDF2 и заодно
    // дозаписываем доказательство для сервера: у записей прежних сборок его
    // нет, а без него человек не войдёт с другого телефона.
    if (res.needsUpgrade || user.serverProof.isEmpty) {
      final users = _users();
      final i = users.indexWhere((u) => u.phone == key);
      if (i >= 0) {
        users[i] = users[i].copyWith(
            passHash:
                res.needsUpgrade ? await _newHash(password) : null,
            serverProof: user.serverProof.isEmpty
                ? await makeProof(key, password)
                : null);
        await _saveUsers(users);
      }
    }
    await _prefs.setString(_currentKey, ph);
    return null;
  }

  Future<void> logout() => _prefs.remove(_currentKey);
}
