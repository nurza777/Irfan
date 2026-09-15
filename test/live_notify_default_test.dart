import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Уведомления об эфире включаются сами, когда человек разрешил уведомления.
///
/// Главное здесь — не перебить его собственное решение: кто выключил эфир
/// в настройках, не должен обнаружить его снова включённым после того, как
/// разрешил, например, азан.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('разрешил уведомления — эфир включился', () async {
    final s = await SettingsService.create();
    expect(s.liveNotificationsEnabled, isFalse);
    expect(s.liveNotificationsChosen, isFalse);

    final turnedOn = await s.adoptLiveDefault(granted: true, supported: true);
    expect(turnedOn, isTrue);
    expect(s.liveNotificationsEnabled, isTrue);
  });

  test('не разрешил — ничего не включается и выбор не записан', () async {
    final s = await SettingsService.create();
    expect(await s.adoptLiveDefault(granted: false, supported: true), isFalse);
    expect(s.liveNotificationsEnabled, isFalse);
    // Выбор не записан — значит, разрешит позже, и эфир включится тогда.
    expect(s.liveNotificationsChosen, isFalse);
  });

  test('на платформе без пушей эфир не включается', () async {
    final s = await SettingsService.create();
    expect(await s.adoptLiveDefault(granted: true, supported: false), isFalse);
    expect(s.liveNotificationsEnabled, isFalse);
  });

  test('кто выключил эфир сам, тому его не включаем', () async {
    final s = await SettingsService.create();
    await s.setLiveNotificationsEnabled(false);
    expect(await s.adoptLiveDefault(granted: true, supported: true), isFalse);
    expect(s.liveNotificationsEnabled, isFalse);
  });

  test('уже включённый остаётся включённым, повторно не «включается»',
      () async {
    final s = await SettingsService.create();
    await s.setLiveNotificationsEnabled(true);
    expect(await s.adoptLiveDefault(granted: true, supported: true), isFalse);
    expect(s.liveNotificationsEnabled, isTrue);
  });
}
