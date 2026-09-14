import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/notification_service.dart';
import 'package:irfan/services/prayer_service.dart';
import 'package:irfan/services/private_zikr_service.dart';
import 'package:irfan/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Бишкек — координаты берутся из настроек по умолчанию, но для теста
/// важна только сама возможность посчитать времена намаза.
const _bishkek = AppLocation(42.87, 74.59, 'Бишкек');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('обеты не вытесняют напоминания о намазе из системного лимита',
      () async {
    final settings = await SettingsService.create();
    await settings.setNotificationsEnabled(true);
    final zikrs = await PrivateZikrService.create();

    // Восемь обетов по три напоминания в день. Раньше их планировали
    // первыми и со своим отдельным потолком в пятьсот штук: они занимали
    // все ~64 слота iOS, и намазы не доходили вообще.
    for (var i = 0; i < 8; i++) {
      await zikrs.add(
        title: 'Обет $i',
        target: 100,
        reminders: const [
          ZikrReminder(7, 0),
          ZikrReminder(13, 0),
          ZikrReminder(21, 0),
        ],
      );
    }

    final now = DateTime.now();
    final prayers =
        NotificationService.planPrayers(settings, _bishkek, 10, now);
    final vows = NotificationService.planZikrs(zikrs, 10, now);

    // Кандидатов заведомо больше лимита — иначе тест ничего не проверяет.
    expect(prayers.length + vows.length,
        greaterThan(NotificationService.maxPending));

    final all = [...vows, ...prayers]
      ..sort((a, b) => a.when.compareTo(b.when));
    final scheduled = all.take(NotificationService.maxPending).toList();

    // Главное: намазы попадают в отправляемый список.
    final prayerTimes = prayers.map((p) => p.when).toSet();
    final scheduledPrayers =
        scheduled.where((p) => prayerTimes.contains(p.when)).length;
    expect(scheduledPrayers, greaterThan(0),
        reason: 'напоминания о намазе вытеснены обетами');

    // И попадают не по остаточному принципу: ближайшие сутки содержат
    // все намазы, какие в них есть.
    final tomorrow = now.add(const Duration(days: 1));
    final prayersNextDay =
        prayers.where((p) => p.when.isBefore(tomorrow)).length;
    final scheduledNextDay = scheduled
        .where((p) => p.when.isBefore(tomorrow) && prayerTimes.contains(p.when))
        .length;
    expect(scheduledNextDay, prayersNextDay,
        reason: 'намазы ближайших суток должны попасть все');
  });

  test('порядок отправки — по времени, а не по виду напоминания', () async {
    final settings = await SettingsService.create();
    await settings.setNotificationsEnabled(true);
    final zikrs = await PrivateZikrService.create();
    await zikrs.add(
        title: 'Обет',
        target: 33,
        reminders: const [ZikrReminder(5, 0), ZikrReminder(23, 30)]);

    final now = DateTime.now();
    final all = [
      ...NotificationService.planZikrs(zikrs, 10, now),
      ...NotificationService.planPrayers(settings, _bishkek, 10, now),
    ]..sort((a, b) => a.when.compareTo(b.when));

    for (var i = 1; i < all.length; i++) {
      expect(all[i].when.isBefore(all[i - 1].when), isFalse,
          reason: 'список должен быть строго по возрастанию времени');
    }
    // Всё запланированное — в будущем: прошедшие времена отбрасываются.
    for (final p in all) {
      expect(p.when.isAfter(now), isTrue);
    }
  });
}
