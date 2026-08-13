import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/account_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Перенос аккаунта на другой телефон.
///
/// Проверяется то, что тихо ломается и не падает: что именно уезжает на
/// сервер (и что НЕ уезжает), что типы значений переживают дорогу и что
/// восстановление не затирает то, чем человек уже успел пожить на новом
/// телефоне.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('что попадает в слепок', () {
    test('история и настройки — да', () {
      for (final k in [
        'tracker_2026-08-01',
        'zikr_counts_2026-08-01',
        'zikr_goals',
        'private_zikrs',
        'private_zikr_done_2026-08-01_obet',
        'coins_spent',
        'coins_redemptions',
        'quran_bookmarks',
        'quran_notes',
        'lesson_at_12345',
        'settings_city',
      ]) {
        expect(AccountBackup.covers(k), isTrue, reason: k);
      }
    });

    test('чужое и устройское — нет', () {
      // auth_users — хеши паролей: на сервер они не уходили никогда.
      // wallpaper_path — путь к файлу на ЭТОМ телефоне.
      // backup_* — служебные метки самого переноса; попади они в слепок,
      // он менялся бы после каждой отправки и уходил бы бесконечно.
      for (final k in [
        'auth_users',
        'auth_current',
        'irfan_staff_token',
        'staff_session',
        'wallpaper_path',
        'api_base_url',
        'live_base_url',
        'onboarding_done',
        'chat_blocked_authors',
        'backup_hash',
        'backup_at',
      ]) {
        expect(AccountBackup.covers(k), isFalse, reason: k);
      }
    });
  });

  test('значения переживают дорогу с сохранением типа', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.tracker_2026-08-01': jsonEncode({'fajr': 'read'}),
      'flutter.coins_spent': 500,
      'flutter.quran_tajwid': true,
      'flutter.quran_font': 28.5,
      'flutter.quran_bookmarks': ['2:255', '18:10'],
      'flutter.auth_users': '[{"passHash":"секрет"}]',
    });
    final snap = AccountBackup.collect(await SharedPreferences.getInstance());

    expect(snap['s'], containsPair('tracker_2026-08-01', '{"fajr":"read"}'));
    expect(snap['i'], containsPair('coins_spent', 500));
    expect(snap['b'], containsPair('quran_tajwid', true));
    expect(snap['d'], containsPair('quran_font', 28.5));
    expect(snap['l'], containsPair('quran_bookmarks', ['2:255', '18:10']));
    // Хеш пароля не уезжает ни в одну из корзин.
    expect(jsonEncode(snap), isNot(contains('passHash')));

    // Слепок должен пережить JSON: сервер хранит его как текст.
    final back = jsonDecode(jsonEncode(snap)) as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    await AccountBackup.apply(p, back);
    expect(p.getString('tracker_2026-08-01'), '{"fajr":"read"}');
    expect(p.getInt('coins_spent'), 500);
    expect(p.getBool('quran_tajwid'), true);
    expect(p.getDouble('quran_font'), 28.5);
    expect(p.getStringList('quran_bookmarks'), ['2:255', '18:10']);
  });

  test('прожитое на новом телефоне не затирается', () async {
    // Человек поставил приложение, помолился день — и только потом вспомнил
    // про перенос. Его сегодняшний день важнее записи из слепка.
    SharedPreferences.setMockInitialValues({
      'flutter.tracker_2026-08-05': jsonEncode({'fajr': 'read'}),
      'flutter.settings_city': 'Ош',
    });
    final p = await SharedPreferences.getInstance();
    await AccountBackup.apply(p, {
      's': {
        'tracker_2026-08-05': jsonEncode({'fajr': 'missed'}),
        'tracker_2026-08-04': jsonEncode({'isha': 'read'}),
        'settings_city': 'Бишкек',
      },
    });
    expect(p.getString('tracker_2026-08-05'), jsonEncode({'fajr': 'read'}));
    expect(p.getString('tracker_2026-08-04'), jsonEncode({'isha': 'read'}));
    expect(p.getString('settings_city'), 'Ош');
  });

  test('потраченное берётся наибольшее', () async {
    // Иначе восстановление вернуло бы в кошелёк коины, уже обменянные на
    // чётки: слепок могли снять до выкупа.
    SharedPreferences.setMockInitialValues({'flutter.coins_spent': 200});
    final p = await SharedPreferences.getInstance();
    await AccountBackup.apply(p, {
      'i': {'coins_spent': 500}
    }, serverSpent: 700);
    expect(p.getInt('coins_spent'), 700);

    SharedPreferences.setMockInitialValues({'flutter.coins_spent': 900});
    final p2 = await SharedPreferences.getInstance();
    await AccountBackup.apply(p2, {
      'i': {'coins_spent': 500}
    }, serverSpent: 700);
    expect(p2.getInt('coins_spent'), 900);
  });

  test('история выкупов сливается по коду', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.coins_redemptions': jsonEncode([
        {'code': 'IRF-AAA', 'title': 'Тасбих', 'cost': 500}
      ]),
    });
    final p = await SharedPreferences.getInstance();
    await AccountBackup.apply(p, {
      's': {
        'coins_redemptions': jsonEncode([
          {'code': 'IRF-AAA', 'title': 'Тасбих', 'cost': 500},
          {'code': 'IRF-BBB', 'title': 'Книга', 'cost': 700},
        ])
      }
    });
    final list = jsonDecode(p.getString('coins_redemptions')!) as List;
    expect(list.length, 2);
    expect(list.map((e) => e['code']), containsAll(['IRF-AAA', 'IRF-BBB']));
  });

  test('мусор в слепке не роняет восстановление', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    await AccountBackup.apply(p, {
      's': {'tracker_2026-08-01': 42, 'auth_users': 'подделка'},
      'i': {'quran_font': 'не число'},
      'l': {'quran_bookmarks': ['2:255', 7]},
      'мусор': 'не корзина',
    });
    // Ключ не своего типа пропущен, чужой ключ не принят вопреки слепку.
    expect(p.getString('tracker_2026-08-01'), isNull);
    expect(p.containsKey('auth_users'), isFalse);
    expect(p.getStringList('quran_bookmarks'), ['2:255']);
  });
}
