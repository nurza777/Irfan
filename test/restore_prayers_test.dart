import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/prayer_service.dart';
import 'package:irfan/services/tracker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('восстановленный намаз уходит из пропущенных, но не в прочитанные',
      () async {
    final tracker = await TrackerService.create();
    final day = DateTime(2026, 9, 1);

    await tracker.setStatus(day, PrayerKey.fajr, PrayerStatus.missed);
    expect(tracker.missedCount(day), 1);
    expect(tracker.restoredCount(day), 0);

    await tracker.setStatus(day, PrayerKey.fajr, PrayerStatus.restored);
    expect(tracker.missedCount(day), 0);
    expect(tracker.restoredCount(day), 1);
    // Прочитанным вовремя он не становится — в этом весь смысл разделения.
    expect(tracker.readCount(day), 0);
  });

  test('коины за восстановление не начисляются', () async {
    final tracker = await TrackerService.create();
    final day = DateTime(2026, 9, 1);

    await tracker.setStatus(day, PrayerKey.fajr, PrayerStatus.read);
    final withRead = tracker.totalReadCount();

    // Иначе можно было бы отметить год пропусков и «восстановить» их разом,
    // получив коины за то, чего приложение никак не проверяет.
    await tracker.setStatus(day, PrayerKey.dhuhr, PrayerStatus.restored);
    expect(tracker.totalReadCount(), withRead);
  });

  test('серия дней не чинится задним числом', () async {
    final tracker = await TrackerService.create();
    final day = DateTime(2026, 9, 1);
    for (final k in PrayerKey.values.where((k) => k.isPrayer)) {
      await tracker.setStatus(day, k, PrayerStatus.restored);
    }
    expect(tracker.isFullDay(day), isFalse,
        reason: 'полный день — это пять намазов, прочитанных вовремя');
  });

  test('список пропущенных: свежие сверху, восстановленных в нём нет',
      () async {
    final tracker = await TrackerService.create();
    final older = DateTime(2026, 8, 30);
    final newer = DateTime(2026, 9, 2);

    await tracker.setStatus(older, PrayerKey.isha, PrayerStatus.missed);
    await tracker.setStatus(newer, PrayerKey.fajr, PrayerStatus.missed);
    await tracker.setStatus(newer, PrayerKey.asr, PrayerStatus.missed);

    var list = tracker.missedPrayers();
    expect(list.length, 3);
    expect(list.first.day, newer, reason: 'свежие дни должны идти первыми');

    await tracker.setStatus(newer, PrayerKey.fajr, PrayerStatus.restored);
    list = tracker.missedPrayers();
    expect(list.length, 2);
    expect(list.any((m) => m.prayer == PrayerKey.fajr), isFalse);
  });

  test('статистика периода считает восстановленные отдельно', () async {
    final tracker = await TrackerService.create();
    final day = DateTime(2026, 9, 1);

    await tracker.setStatus(day, PrayerKey.fajr, PrayerStatus.read);
    await tracker.setStatus(day, PrayerKey.dhuhr, PrayerStatus.restored);
    await tracker.setStatus(day, PrayerKey.asr, PrayerStatus.missed);

    final stats = tracker.stats(day, day);
    expect(stats.read, 1);
    expect(stats.restored, 1);
    expect(stats.missed, 1);
  });

  test('старые записи без нового статуса читаются по-прежнему', () async {
    SharedPreferences.setMockInitialValues({
      'tracker_2026-09-01': '{"fajr":"read","dhuhr":"missed","asr":"нечто"}',
    });
    final tracker = await TrackerService.create();
    final day = DateTime(2026, 9, 1);
    expect(tracker.statusOf(day, PrayerKey.fajr), PrayerStatus.read);
    expect(tracker.statusOf(day, PrayerKey.dhuhr), PrayerStatus.missed);
    // Незнакомое значение не должно ронять экран.
    expect(tracker.statusOf(day, PrayerKey.asr), PrayerStatus.pending);
  });
}
