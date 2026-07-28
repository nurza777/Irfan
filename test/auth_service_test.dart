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
        gender: Gender.male,
        phone: '0555123456');
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
        gender: Gender.male,
        phone: '0555123456');

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


  test('регистрация требует телефон — по нему приходит код подтверждения',
      () async {
    final auth = await AuthService.create();
    final err = await auth.register(
        name: 'Тест',
        email: 'a@b.kg',
        password: 'secret1',
        age: 20,
        gender: Gender.male);
    expect(err, isNotNull, reason: 'без телефона регистрация не проходит');
  });

  test('телефон приводится к международному виду', () {
    // Локальные кыргызские форматы — к +996; мусор отбрасывается.
    expect(normalizePhone('0555123456'), '+996555123456');
    expect(normalizePhone('555123456'), '+996555123456');
    expect(normalizePhone('0555 12 34 56'), '+996555123456');
    expect(normalizePhone('+996 555 123 456'), '+996555123456');
    expect(normalizePhone('123'), '');
    expect(normalizePhone(''), '');
  });

  test('анкета сохраняется в аккаунте', () async {
    final auth = await AuthService.create();
    await auth.register(
        name: 'Тест',
        email: 'a@b.kg',
        password: 'secret1',
        age: 20,
        gender: Gender.male,
        phone: '0700111222',
        city: 'Ош');
    expect(auth.current!.phone, '+996700111222');
    expect(auth.current!.city, 'Ош');
  });
}
