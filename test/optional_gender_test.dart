import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('регистрация проходит без указания пола', () async {
    final auth = await AuthService.create();
    // App Store вернул приложение по 5.1.1(v) именно за обязательный пол:
    // требовать можно только те данные, без которых приложение не работает.
    final err = await auth.register(
      name: 'Тест',
      phone: '+996555111222',
      password: 'секрет123',
      birthDate: DateTime(1996, 5, 20),
      gender: null,
    );
    expect(err, isNull, reason: 'пустой пол не должен мешать регистрации');
    expect(auth.current!.gender, isNull);
  });

  test('указанный пол сохраняется и переживает перечитывание', () async {
    final auth = await AuthService.create();
    await auth.register(
      name: 'Тест',
      phone: '+996555111333',
      password: 'секрет123',
      birthDate: DateTime(1996, 5, 20),
      gender: Gender.female,
    );
    expect(auth.current!.gender, Gender.female);

    final again = await AuthService.create();
    expect(again.current!.gender, Gender.female,
        reason: 'пол должен читаться обратно из хранилища');
  });

  test('старая запись без поля пола читается как «не указан»', () async {
    final u = UserAccount.fromJson({
      'name': 'Старый',
      'phone': '+996555111444',
      'passHash': 'x',
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'age': 40,
      'gender': '',
    });
    // Прежде здесь молча подставлялся мужской пол — то есть приложение
    // придумывало за человека данные, которых он не давал.
    expect(u.gender, isNull);
    expect(u.toJson()['gender'], '');
  });

  test('остальные проверки анкеты остались на месте', () async {
    final auth = await AuthService.create();
    expect(
        await auth.register(
            name: '', phone: '+996555111555', password: 'секрет123',
            birthDate: DateTime(1996, 5, 20), gender: null),
        isNotNull);
    expect(
        await auth.register(
            name: 'Тест', phone: '+996555111666', password: '123',
            birthDate: DateTime(1996, 5, 20), gender: null),
        isNotNull);
    // Дата рождения обязательна — без неё возраст неоткуда взять.
    expect(
        await auth.register(
            name: 'Тест', phone: '+996555111777', password: 'секрет123',
            birthDate: null, gender: null),
        isNotNull);
    // И она должна давать разумный возраст: годовалый ученик — это промах
    // в выборе года, а не настоящая анкета.
    expect(
        await auth.register(
            name: 'Тест', phone: '+996555111888', password: 'секрет123',
            birthDate: DateTime.now().subtract(const Duration(days: 365)),
            gender: null),
        isNotNull);
  });

  test('возраст считается из даты рождения и не устаревает', () async {
    final auth = await AuthService.create();
    final now = DateTime.now();
    // День рождения был вчера — значит ровно 30.
    final had = DateTime(now.year - 30, now.month, now.day)
        .subtract(const Duration(days: 1));
    await auth.register(
        name: 'Тест',
        phone: '+996555112000',
        password: 'секрет123',
        birthDate: had,
        gender: null);
    expect(auth.current!.age, 30);
    expect(auth.current!.birthDate, isNotNull);

    // Раньше в анкете лежало застывшее число, и через год оно врало.
    // Теперь хранится дата, а возраст пересчитывается при каждом обращении.
    final again = await AuthService.create();
    expect(again.current!.age, 30);
  });

  test('день рождения ещё не наступил — год не засчитан', () async {
    final now = DateTime.now();
    // Родился 30 лет назад, но на день позже сегодняшнего числа.
    final soon = DateTime(now.year - 30, now.month, now.day)
        .add(const Duration(days: 1));
    final u = UserAccount(
      name: 'Тест',
      phone: '+996555112111',
      passHash: 'x',
      createdAt: now,
      storedAge: 0,
      birthDate: soon,
      gender: null,
    );
    expect(u.age, 29);
  });

  test('старая запись без даты рождения читает сохранённое число', () {
    final u = UserAccount.fromJson({
      'name': 'Старый',
      'phone': '+996555112222',
      'passHash': 'x',
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'age': 42,
    });
    expect(u.birthDate, isNull);
    expect(u.age, 42, reason: 'записи прежних сборок не должны обнулиться');
  });
}
