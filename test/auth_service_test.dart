import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('регистрация → вход с верным паролем, отказ с неверным', () async {
    final auth = await AuthService.create();
    final err = await auth.register(
        name: 'Тест',
        email: 'a@b.kg',
        password: 'secret1',
        age: 20,
        gender: Gender.male);
    expect(err, isNull);

    final logout = auth;
    await logout.logout();

    expect(await auth.login(email: 'a@b.kg', password: 'secret1'), isNull);
    expect(await auth.login(email: 'a@b.kg', password: 'wrong'),
        isNotNull);
    // email нечувствителен к регистру
    expect(await auth.login(email: 'A@B.KG', password: 'secret1'), isNull);
  });

  test('пароль хранится как PBKDF2, не как открытый текст/простой SHA-256',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final auth = await AuthService.create();
    await auth.register(
        name: 'Тест',
        email: 'a@b.kg',
        password: 'secret1',
        age: 20,
        gender: Gender.male);

    final raw = prefs.getString('auth_users')!;
    expect(raw.contains('secret1'), isFalse, reason: 'нет открытого пароля');
    final legacy =
        sha256.convert(utf8.encode('a@b.kg:secret1')).toString();
    expect(raw.contains(legacy), isFalse, reason: 'не простой SHA-256');
    expect(raw.contains('pbkdf2\$'), isTrue, reason: 'формат PBKDF2');
  });

  test('старый несолёный SHA-256 аккаунт входит и мигрирует на PBKDF2',
      () async {
    final prefs = await SharedPreferences.getInstance();
    // Готовим «legacy» аккаунт вручную, как хранила старая версия.
    final legacyHash =
        sha256.convert(utf8.encode('old@b.kg:pass12')).toString();
    final legacyUser = {
      'name': 'Старый',
      'email': 'old@b.kg',
      'passHash': legacyHash,
      'createdAt': DateTime.now().toIso8601String(),
      'age': 30,
      'gender': 'male',
    };
    await prefs.setString('auth_users', jsonEncode([legacyUser]));

    final auth = await AuthService.create();
    // Вход по старому паролю должен работать…
    expect(await auth.login(email: 'old@b.kg', password: 'pass12'), isNull);
    // …и прозрачно пересохранить хеш в новом формате.
    expect(prefs.getString('auth_users')!.contains('pbkdf2\$'), isTrue);
    expect(prefs.getString('auth_users')!.contains(legacyHash), isFalse);
    // Повторный вход уже по PBKDF2 — тоже успешен.
    await auth.logout();
    expect(await auth.login(email: 'old@b.kg', password: 'pass12'), isNull);
    expect(await auth.login(email: 'old@b.kg', password: 'nope'), isNotNull);
  });
}
