import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/notification_service.dart';
import 'package:irfan/services/prayer_service.dart';
import 'package:irfan/services/settings_service.dart';
import 'package:irfan/services/tracker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bishkek = AppLocation(42.87, 74.59, 'Бишкек');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('вопрос ставится через заданную паузу после времени намаза', () async {
    final settings = await SettingsService.create();
    await settings.setAskDelayMinutes(30);
    final now = DateTime.now();

    final asks = NotificationService.planAsk(settings, _bishkek, null, 3, now);
    expect(asks, isNotEmpty);

    // У каждого вопроса время = время намаза + пауза. Проверяем по первому
    // из будущих: считаем время намаза тем же способом, что и планировщик.
    final first = asks.first;
    final day = DateTime(first.when.year, first.when.month, first.when.day);
    final times = PrayerService.timesFor(day, _bishkek,
        method: settings.method, madhab: settings.madhab);
    final matched = SettingsService.notifiablePrayers.any(
        (k) => times[k].add(const Duration(minutes: 30)) == first.when);
    expect(matched, isTrue,
        reason: 'время вопроса должно равняться времени намаза плюс пауза');
  });

  test('об уже отмеченном намазе не спрашивают', () async {
    final settings = await SettingsService.create();
    await settings.setAskDelayMinutes(10);
    final tracker = await TrackerService.create();
    // Время задаём явно, а не берём текущее. С DateTime.now() тест зависел
    // от часа запуска: вечером все намазы уже позади, вопросов на сегодня
    // не планируется, и проверка «до отметки вопросы есть» падала на ровном
    // месте. 3 часа ночи — до фаджра, впереди все пять.
    final now = DateTime(2026, 9, 10, 3);

    final before =
        NotificationService.planAsk(settings, _bishkek, tracker, 2, now);
    expect(before, isNotEmpty);

    for (final k in SettingsService.notifiablePrayers) {
      await tracker.setStatus(now, k, PrayerStatus.read);
    }

    final after =
        NotificationService.planAsk(settings, _bishkek, tracker, 2, now);

    // Считаем по НАГРУЗКЕ, а не по времени: у завтрашнего утреннего намаза
    // вопрос попадает в ближайшие сутки по часам, но относится к другому дню.
    final key = TrackerService.dayKeyOf(now);
    int forToday(List<PlannedNotification> list) =>
        list.where((a) => (a.payload ?? '').contains('|$key|')).length;

    expect(forToday(before), greaterThan(0));
    expect(forToday(after), 0,
        reason: 'после отметки вопросы за этот день должны исчезнуть');
    // Завтрашние при этом остаются — их никто не отмечал.
    expect(after, isNotEmpty);
  });

  test('выключенный вопрос ничего не планирует', () async {
    final settings = await SettingsService.create();
    await settings.setAskEnabled(false);
    expect(
        NotificationService.planAsk(
            settings, _bishkek, null, 3, DateTime.now()),
        isEmpty);
  });

  test('ответ «Да» из уведомления отмечает намаз прочитанным', () async {
    final tracker = await TrackerService.create();
    final day = DateTime(2026, 9, 3);
    expect(tracker.statusOf(day, PrayerKey.fajr), PrayerStatus.pending);

    await NotificationService.applyAskResponse(const NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      actionId: 'ask_yes',
      payload: 'ask|2026-09-03|fajr',
    ));

    await tracker.reload();
    expect(tracker.statusOf(day, PrayerKey.fajr), PrayerStatus.read);
  });

  test('ответ «Нет» отмечает пропущенным, чужая нагрузка игнорируется',
      () async {
    final tracker = await TrackerService.create();
    final day = DateTime(2026, 9, 3);

    await NotificationService.applyAskResponse(const NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      actionId: 'ask_no',
      payload: 'ask|2026-09-03|isha',
    ));
    await tracker.reload();
    expect(tracker.statusOf(day, PrayerKey.isha), PrayerStatus.missed);

    // Нажатие по самому уведомлению (без кнопки) ничего не отмечает:
    // человек просто открыл приложение, ответа он не давал.
    await NotificationService.applyAskResponse(const NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: 'ask|2026-09-03|maghrib',
    ));
    await tracker.reload();
    expect(tracker.statusOf(day, PrayerKey.maghrib), PrayerStatus.pending);

    // Зато вопрос запоминается: приложение задаст его окном. Кнопки iOS
    // показывает только у развёрнутого уведомления, и нажатие по баннеру —
    // самый частый способ «ответить», который иначе пропал бы впустую.
    expect(NotificationService.pendingAsk.value, 'ask|2026-09-03|maghrib');

    // Мусор в нагрузке не должен ничего портить.
    await NotificationService.applyAskResponse(const NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      actionId: 'ask_yes',
      payload: 'что-то не то',
    ));
    await tracker.reload();
    expect(tracker.statusOf(day, PrayerKey.dhuhr), PrayerStatus.pending);
  });

  test('нажатие по чужому уведомлению вопрос не запоминает', () async {
    NotificationService.pendingAsk.value = null;
    await NotificationService.applyAskResponse(const NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: 'live|2026-09-03',
    ));
    expect(NotificationService.pendingAsk.value, isNull);
  });

  test('ответ из окна приложения отмечает намаз так же, как кнопка', () async {
    final tracker = await TrackerService.create();
    final day = DateTime(2026, 9, 3);

    await NotificationService.answerAsk('ask|2026-09-03|asr', true);
    await tracker.reload();
    expect(tracker.statusOf(day, PrayerKey.asr), PrayerStatus.read);

    await NotificationService.answerAsk('ask|2026-09-03|dhuhr', false);
    await tracker.reload();
    expect(tracker.statusOf(day, PrayerKey.dhuhr), PrayerStatus.missed);
  });
}
