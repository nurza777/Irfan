import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'lang.dart';
import 'prayer_service.dart';
import 'private_zikr_service.dart';
import 'settings_service.dart';

/// Локальные напоминания о намазе (азан). Работают офлайн: времена намаза
/// считаются на устройстве, уведомления планируются на ближайшие дни через
/// системный планировщик — сервер не нужен.
class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
    } catch (_) {
      // Не удалось определить зону — планировщик использует локальную по умолчанию.
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Разрешение спросим отдельно (когда пользователь включит напоминания).
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin));
    _inited = true;
  }

  /// Спрашивает системное разрешение на уведомления. true — разрешено.
  static Future<bool> requestPermission() async {
    await init();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final ok = await ios.requestPermissions(
          alert: true, badge: true, sound: true);
      return ok ?? false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ok = await android?.requestNotificationsPermission();
    return ok ?? true;
  }

  /// Перепланирует все напоминания на ближайшие [days] дней по текущим
  /// настройкам и времени намаза. Вызывать при старте и при изменении
  /// настроек/локации.
  static Future<void> reschedule({
    required SettingsService settings,
    required AppLocation location,
    PrivateZikrService? privateZikrs,
    int days = 4,
  }) async {
    await init();
    await _plugin.cancelAll();
    // Напоминания о закрытых зикрах ставятся независимо от намазов: человек
    // мог отключить азан, но оставить свои обеты.
    if (privateZikrs != null) {
      await _scheduleZikrs(privateZikrs, days);
    }
    if (!settings.notificationsEnabled) return;
    final prayers = settings.notifyPrayers;
    if (prayers.isEmpty) return;

    final before = settings.notifyBeforeMinutes;
    final now = DateTime.now();
    var id = 0;
    for (var d = 0; d < days; d++) {
      final day = now.add(Duration(days: d));
      final times = PrayerService.timesFor(day, location,
          method: settings.method, madhab: settings.madhab);
      for (final k in SettingsService.notifiablePrayers) {
        if (!prayers.contains(k)) continue;
        final when = times[k].subtract(Duration(minutes: before));
        if (!when.isAfter(now)) continue;
        await _scheduleOne(id++, k, when, before);
        if (id >= 60) return; // iOS держит максимум ~64 запланированных
      }
    }
  }

  /// Напоминания о закрытых зикрах — в заданные часы каждый день.
  /// Идентификаторы со сдвигом 10000, чтобы не столкнуться с намазами.
  static Future<void> _scheduleZikrs(
      PrivateZikrService svc, int days) async {
    final now = DateTime.now();
    var id = 10000;
    for (final z in svc.all) {
      for (final r in z.reminders) {
        for (var d = 0; d < days; d++) {
          final day = now.add(Duration(days: d));
          final when =
              DateTime(day.year, day.month, day.day, r.hour, r.minute);
          if (!when.isAfter(now)) continue;
          // Если на этот день зикр уже закрыт, дёргать человека незачем.
          if (d == 0 && svc.isClosedToday(day, z)) continue;
          final left = svc.leftToday(day, z);
          try {
            await _plugin.zonedSchedule(
              id++,
              t('Зикр'),
              appLang == Lang.ky
                  ? '${z.title} — ${left > 0 ? left : z.target} калды'
                  : '${z.title} — осталось ${left > 0 ? left : z.target}',
              tz.TZDateTime.from(when, tz.local),
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'private_zikr',
                  'Закрытые зикры',
                  importance: Importance.defaultImportance,
                  priority: Priority.defaultPriority,
                ),
                iOS: DarwinNotificationDetails(),
              ),
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          } catch (e) {
            debugPrint('zikr notification error: $e');
          }
          if (id > 10500) return;   // разумный потолок
        }
      }
    }
  }

  static Future<void> _scheduleOne(
      int id, PrayerKey k, DateTime when, int before) async {
    final name = t(k.titleRu);
    final ky = appLang == Lang.ky;
    final title = before > 0
        ? (ky ? '$name жакындады' : 'Скоро $name')
        : (ky ? 'Намаз убактысы — $name' : 'Время намаза — $name');
    final body = before > 0
        ? (ky
            ? '$name $before мүнөттөн кийин. Намазга даярданыңыз.'
            : '$name через $before мин. Приготовьтесь к намазу.')
        : (ky
            ? '$name намазынын убактысы кирди. Өткөрүп жибербеңиз.'
            : 'Наступило время намаза $name. Не пропустите.');
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'prayer_times',
            'Времена намаза',
            channelDescription: 'Напоминания о наступлении времени намаза',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('notification schedule error: $e');
    }
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}
