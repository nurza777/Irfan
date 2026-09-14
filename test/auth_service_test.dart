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
        phone: '0555123456',
        password: 'secret1',
        birthDate: DateTime(1996, 5, 20),
        gender: Gender.male);
    expect(err, isNull);

    final logout = auth;
    await logout.logout();

    expect(await auth.login(phone: '0555123456', password: 'secret1'), isNull);
    expect(await auth.login(phone: '0555123456', password: 'wrong'),
        isNotNull);
    // номер принимается в любом написании
    expect(await auth.login(phone: '+996555123456', password: 'secret1'), isNull);
  });

  test('пароль хранится как PBKDF2, не как открытый текст/простой SHA-256',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final auth = await AuthService.create();
    await auth.register(
        name: 'Тест',
        phone: '0555123456',
        password: 'secret1',
        birthDate: DateTime(1996, 5, 20),
        gender: Gender.male);

    final raw = prefs.getString('auth_users')!;
    expect(raw.contains('secret1'), isFalse, reason: 'нет открытого пароля');
    final legacy =
        sha256.convert(utf8.encode('+996555123456:secret1')).toString();
    expect(raw.contains(legacy), isFalse, reason: 'не простой SHA-256');
    expect(raw.contains('pbkdf2\$'), isTrue, reason: 'формат PBKDF2');
  });

  test('аккаунт старой сборки (опознавался почтой) входит и мигрирует',
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
    expect(await auth.login(phone: 'old@b.kg', password: 'pass12'), isNull);
    // …и прозрачно пересохранить хеш в новом формате.
    expect(prefs.getString('auth_users')!.contains('pbkdf2\$'), isTrue);
    expect(prefs.getString('auth_users')!.contains(legacyHash), isFalse);
    // Повторный вход уже по PBKDF2 — тоже успешен.
    await auth.logout();
    expect(await auth.login(phone: 'old@b.kg', password: 'pass12'), isNull);
    expect(await auth.login(phone: 'old@b.kg', password: 'nope'), isNotNull);
  });


  test('регистрация требует телефон — он же опознаватель аккаунта',
      () async {
    final auth = await AuthService.create();
    final err = await auth.register(
        name: 'Тест',
        phone: '',
        password: 'secret1',
        birthDate: DateTime(1996, 5, 20),
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

  test('доказательство пароля одинаково на любом телефоне', () async {
    // Ради этого свойства оно и заведено: человек вводит номер и пароль на
    // НОВОМ телефоне, где никакой местной соли нет, и сервер узнаёт его.
    final a = await AuthService.makeProof('0555123456', 'secret1');
    final b = await AuthService.makeProof('+996 555 123 456', 'secret1');
    expect(a, isNotEmpty);
    expect(b, a, reason: 'номер в любой записи даёт то же значение');

    final other = await AuthService.makeProof('0555123456', 'secret2');
    expect(other, isNot(a), reason: 'другой пароль — другое значение');

    final another = await AuthService.makeProof('0700111222', 'secret1');
    expect(another, isNot(a),
        reason: 'соль из номера: один пароль у разных людей не совпадает');

    expect(await AuthService.makeProof('', 'secret1'), '');
    expect(await AuthService.makeProof('0555123456', ''), '');
  });

  test('доказательство сохраняется при регистрации', () async {
    final auth = await AuthService.create();
    await auth.register(
        name: 'Тест',
        phone: '0555123456',
        password: 'secret1',
        birthDate: DateTime(1996, 5, 20),
        gender: Gender.male);
    final want = await AuthService.makeProof('0555123456', 'secret1');
    expect(auth.current!.serverProof, want);

    // И переживает перечитывание хранилища: значение уходит на сервер при
    // каждом отчёте, а не только сразу после регистрации.
    final again = await AuthService.create();
    expect(again.current!.serverProof, want);
  });

  test('вход дописывает доказательство старой записи', () async {
    final auth = await AuthService.create();
    await auth.register(
        name: 'Тест',
        phone: '0555123456',
        password: 'secret1',
        birthDate: DateTime(1996, 5, 20),
        gender: Gender.male);
    // Убираем доказательство, как будто запись завела прежняя сборка.
    final prefs = await SharedPreferences.getInstance();
    final users = jsonDecode(prefs.getString('auth_users')!) as List;
    (users.first as Map).remove('serverProof');
    await prefs.setString('auth_users', jsonEncode(users));

    final fresh = await AuthService.create();
    expect(fresh.current!.serverProof, isEmpty);
    expect(await fresh.login(phone: '0555123456', password: 'secret1'), isNull);
    expect(fresh.current!.serverProof,
        await AuthService.makeProof('0555123456', 'secret1'));
  });

  test('hasLocal отличает свой телефон от чужого', () async {
    final auth = await AuthService.create();
    await auth.register(
        name: 'Тест',
        phone: '0555123456',
        password: 'secret1',
        birthDate: DateTime(1996, 5, 20),
        gender: Gender.male);
    expect(auth.hasLocal('0555123456'), isTrue);
    expect(auth.hasLocal('+996555123456'), isTrue);
    // По этому признаку вход решает, идти ли за аккаунтом на сервер.
    expect(auth.hasLocal('0700999888'), isFalse);
    expect(auth.hasLocal(''), isFalse);
  });

  test('анкета сохраняется в аккаунте', () async {
    final auth = await AuthService.create();
    await auth.register(
        name: 'Тест',
        phone: '0700111222',
        password: 'secret1',
        birthDate: DateTime(1996, 5, 20),
        gender: Gender.male,
        city: 'Ош');
    expect(auth.current!.phone, '+996700111222');
    expect(auth.current!.city, 'Ош');
  });
}
