import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/prayer_service.dart';
import 'package:irfan/services/tracker_service.dart';
import 'package:irfan/services/zikr_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Подсчёт коинов кэширует прошлые дни и перечитывает только сегодняшний —
/// иначе каждый тап счётчика перечитывал всё хранилище. Ошибка в кэше не
/// упала бы, а тихо исказила баланс, поэтому проверяем числа.
///
/// Попутно закреплена защита от накрутки: коины идут за каждые 33 повтора,
/// но только в пределах дневной цели зикра (у СубханаЛлах она 33, то есть
/// не больше одного коина в день).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String dayKey(String prefix, DateTime d) =>
      '$prefix${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';

  final today = DateTime.now();
  final yesterday = today.subtract(const Duration(days: 1));
  final longAgo = today.subtract(const Duration(days: 40));

  group('зикры', () {
    test('складывает прошлые дни и сегодняшний', () async {
      SharedPreferences.setMockInitialValues({
        // 66 повторов, но дневная цель 33 → всё равно 1 коин.
        'flutter.${dayKey('zikr_counts_', yesterday)}':
            jsonEncode({'subhanallah': 66}),
        // 33 → 1 коин; 10 → ни одного.
        'flutter.${dayKey('zikr_counts_', longAgo)}':
            jsonEncode({'alhamdulillah': 33, 'allahuakbar': 10}),
        'flutter.${dayKey('zikr_counts_', today)}':
            jsonEncode({'subhanallah': 33}),
      });
      final z = await ZikrService.create();
      expect(z.totalCoins(), 3);
    });

    test('сегодняшний прирост виден сразу, кэш его не замораживает', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${dayKey('zikr_counts_', yesterday)}':
            jsonEncode({'subhanallah': 33}),
      });
      final z = await ZikrService.create();
      expect(z.totalCoins(), 1);

      // 32 повтора сегодня — коина ещё нет.
      for (var i = 0; i < 32; i++) {
        await z.increment(today, 'subhanallah');
      }
      expect(z.totalCoins(), 1);

      // 33-й повтор закрывает дневную цель и даёт коин.
      await z.increment(today, 'subhanallah');
      expect(z.totalCoins(), 2);

      // Дальнейшие нажатия сверх цели коинов не приносят.
      for (var i = 0; i < 100; i++) {
        await z.increment(today, 'subhanallah');
      }
      expect(z.totalCoins(), 2);

      // Второй зикр за тот же день считается отдельно.
      for (var i = 0; i < 33; i++) {
        await z.increment(today, 'alhamdulillah');
      }
      expect(z.totalCoins(), 3);
    });

    test('сброс сегодняшнего зикра уменьшает баланс', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${dayKey('zikr_counts_', today)}':
            jsonEncode({'subhanallah': 33, 'alhamdulillah': 33}),
      });
      final z = await ZikrService.create();
      expect(z.totalCoins(), 2);
      await z.reset(today, 'subhanallah');
      expect(z.totalCoins(), 1);
    });

    test('прошлые дни не пересчитываются, но и не теряются', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${dayKey('zikr_counts_', longAgo)}':
            jsonEncode({'subhanallah': 33}),
        'flutter.${dayKey('zikr_counts_', yesterday)}':
            jsonEncode({'alhamdulillah': 33}),
      });
      final z = await ZikrService.create();
      // Многократный вызов не должен ни задваивать, ни терять прошлое.
      expect(z.totalCoins(), 2);
      expect(z.totalCoins(), 2);
      await z.increment(today, 'subhanallah');
      expect(z.totalCoins(), 2);
    });
  });

  group('трекер намазов', () {
    test('складывает прошлые дни и сегодняшний', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${dayKey('tracker_', yesterday)}': jsonEncode({
          'fajr': 'read',
          'dhuhr': 'read',
          'asr': 'missed',
        }),
        'flutter.${dayKey('tracker_', longAgo)}':
            jsonEncode({'fajr': 'read'}),
        'flutter.${dayKey('tracker_', today)}': jsonEncode({'fajr': 'read'}),
      });
      final t = await TrackerService.create();
      expect(t.totalReadCount(), 4);
    });

    test('отметка сегодняшнего намаза видна сразу', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${dayKey('tracker_', yesterday)}':
            jsonEncode({'fajr': 'read'}),
      });
      final t = await TrackerService.create();
      expect(t.totalReadCount(), 1);

      await t.setStatus(today, PrayerKey.dhuhr, PrayerStatus.read);
      expect(t.totalReadCount(), 2);

      // Пропущенный намаз в счёт не идёт.
      await t.setStatus(today, PrayerKey.asr, PrayerStatus.missed);
      expect(t.totalReadCount(), 2);

      // Передумал: тот же намаз переотмечен прочитанным — не задваивается.
      await t.setStatus(today, PrayerKey.asr, PrayerStatus.read);
      expect(t.totalReadCount(), 3);
    });
  });
}
