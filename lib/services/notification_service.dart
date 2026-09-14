import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'lang.dart';
import 'prayer_service.dart';
import 'private_zikr_service.dart';
import 'settings_service.dart';
import 'tracker_service.dart';

/// Локальные напоминания о намазе (азан). Работают офлайн: времена намаза
/// считаются на устройстве, уведомления планируются на ближайшие дни через
/// системный планировщик — сервер не нужен.
/// Обработчик кнопок «Да»/«Нет» из уведомления, когда приложение ЗАКРЫТО.
///
/// Выполняется в отдельном изоляте: ни состояния приложения, ни его сервисов
/// здесь нет — только хранилище настроек. Поэтому отметка пишется общим
/// методом [TrackerService.applyAnswer], тем же, что и в приложении.
///
/// Аннотация обязательна: без неё функцию выбрасывает древовидная очистка
/// при сборке в релизе, и кнопки перестают работать именно там, где это
/// труднее всего заметить.
@pragma('vm:entry-point')
void handleAskActionBackground(NotificationResponse response) {
  NotificationService.applyAskResponse(response);
}

class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  /// Опознаватель категории с кнопками (iOS) и действий (обе системы).
  static const _askCategory = 'prayer_ask';

  /// Запись азана в бандле приложения (см. tools/add_azan.py).
  static const _azanSound = 'azan.caf';
  static const _actionYes = 'ask_yes';
  static const _actionNo = 'ask_no';

  /// Приложение подписывается сюда, чтобы обновить экран сразу после
  /// ответа из уведомления, пока оно открыто.
  static void Function()? onAnswered;

  /// Вопрос, на который человек ещё не ответил, — потому что вместо кнопки
  /// нажал по самому уведомлению.
  ///
  /// Кнопки «Да»/«Нет» iOS показывает только у РАЗВЁРНУТОГО уведомления:
  /// баннер нужно потянуть вниз, на замке — нажать и подержать. Заставить
  /// систему раскрыть его сразу нельзя, такой возможности в API нет. Поэтому
  /// обычное нажатие тоже считаем за попытку ответить: открываем приложение
  /// и спрашиваем то же самое окном поверх экрана. Одно касание вместо
  /// удержания, а ответ ложится в те же записи.
  static final ValueNotifier<String?> pendingAsk = ValueNotifier<String?>(null);

  /// Разбирает ответ и отмечает намаз. Формат полезной нагрузки —
  /// `ask|ГГГГ-ММ-ДД|namaz`; собирается в [_askPlan].
  static Future<void> applyAskResponse(NotificationResponse r) async {
    final parts = (r.payload ?? '').split('|');
    final ours = parts.length == 3 && parts.first == 'ask';
    final action = r.actionId;
    if (action != _actionYes && action != _actionNo) {
      // Нажатие по самому уведомлению: отмечать молча нельзя — человек ответа
      // не давал. Запоминаем вопрос, окно покажет [RootScreen].
      if (ours &&
          r.notificationResponseType ==
              NotificationResponseType.selectedNotification) {
        pendingAsk.value = r.payload;
      }
      return;
    }
    if (!ours) return;
    await TrackerService.applyAnswer(
      parts[1],
      parts[2],
      action == _actionYes ? PrayerStatus.read : PrayerStatus.missed,
    );
    onAnswered?.call();
  }

  /// Отмечает намаз ответом из окна приложения. Нагрузка — та же строка
  /// `ask|ГГГГ-ММ-ДД|namaz`, что и в уведомлении: разбор один на оба пути.
  static Future<void> answerAsk(String payload, bool yes) async {
    final parts = payload.split('|');
    if (parts.length != 3 || parts.first != 'ask') return;
    await TrackerService.applyAnswer(
        parts[1], parts[2], yes ? PrayerStatus.read : PrayerStatus.missed);
    onAnswered?.call();
  }

  /// Вопрос, по которому приложение только что запустили с нуля.
  ///
  /// Когда приложение убито, нажатие по уведомлению не приходит в обработчик:
  /// система просто запускает процесс, а повод запуска лежит отдельно. Без
  /// этой проверки вопрос терялся бы именно в самом частом случае — телефон
  /// лежал в кармане, приложение давно выгружено.
  static Future<void> consumeLaunchPayload() async {
    await init();
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d == null || !d.didNotificationLaunchApp) return;
      final r = d.notificationResponse;
      if (r == null) return;
      if (r.actionId == _actionYes || r.actionId == _actionNo) return;
      final parts = (r.payload ?? '').split('|');
      if (parts.length == 3 && parts.first == 'ask') pendingAsk.value = r.payload;
    } catch (_) {
      // Повод запуска недоступен — не повод падать.
    }
  }

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
    // Категория с кнопками объявляется ЗДЕСЬ: iOS требует зарегистрировать
    // её при запуске, до показа первого уведомления, иначе кнопок не будет.
    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          _askCategory,
          actions: [
            DarwinNotificationAction.plain(_actionYes, t('Да')),
            DarwinNotificationAction.plain(_actionNo, t('Нет')),
          ],
          options: const {
            // Без этого система не покажет кнопки на заблокированном экране —
            // а именно там человек чаще всего и увидит вопрос.
            DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
          },
        ),
      ],
    );
    await _plugin.initialize(
      InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: applyAskResponse,
      onDidReceiveBackgroundNotificationResponse: handleAskActionBackground,
    );
    // Прежний канал без азана оставался бы в системных настройках телефона
    // отдельной строкой — второй «Времена намаза», по которой ничего больше
    // не приходит. Убираем; на новых установках его и не было.
    if (Platform.isAndroid) {
      try {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.deleteNotificationChannel('prayer_times');
      } catch (_) {
        // Канала нет — и хорошо.
      }
    }
    _inited = true;
  }

  /// Спрашивает системное разрешение на уведомления. true — разрешено.
  /// Насколько точно Android разрешает будить приложение.
  ///
  /// Неточный режим система вправе сдвинуть на десятки минут — для азана это
  /// и есть смысл функции, поэтому просим точный, а откатываемся только если
  /// разрешения нет. На iOS значение ни на что не влияет.
  static Future<AndroidScheduleMode> _scheduleMode() async {
    if (!Platform.isAndroid) return AndroidScheduleMode.exactAllowWhileIdle;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final exact = await android?.canScheduleExactNotifications() ?? false;
      return exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (_) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

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

  /// Сколько уведомлений разрешаем себе запланировать разом.
  ///
  /// iOS хранит не больше 64 отложенных уведомлений на приложение и молча
  /// выбрасывает лишние — без ошибки, без предупреждения. Держим запас
  /// в несколько штук на случай, если что-то поставит система.
  @visibleForTesting
  static const maxPending = 60;

  /// Перепланирует все напоминания на ближайшие [days] дней по текущим
  /// настройкам и времени намаза. Вызывать при старте и при изменении
  /// настроек/локации.
  ///
  /// Намазы и обеты планируются ОДНИМ списком, отсортированным по времени.
  /// Раньше у каждого был свой предел (60 у намазов, 500 у обетов), а
  /// системный потолок — общий: обеты ставились первыми и при нескольких
  /// обетах съедали всю квоту, после чего напоминания о намазе не доходили
  /// вовсе. Молча — приложение об этом не узнавало.
  ///
  /// Теперь побеждает то, что случится раньше, независимо от вида. Заодно
  /// это позволило увеличить горизонт: список всё равно обрезается бюджетом,
  /// поэтому лишние дни ничего не ломают, а у того, кто редко открывает
  /// приложение, напоминания живут дольше.
  static Future<void> reschedule({
    required SettingsService settings,
    required AppLocation location,
    PrivateZikrService? privateZikrs,
    TrackerService? tracker,
    int days = 10,
  }) async {
    await init();
    await _plugin.cancelAll();

    final now = DateTime.now();
    final planned = <PlannedNotification>[];

    // Напоминания об обетах ставятся независимо от намазов: человек мог
    // отключить азан, но оставить свои обеты.
    if (privateZikrs != null) {
      planned.addAll(planZikrs(privateZikrs, days, now));
    }
    if (settings.notificationsEnabled) {
      planned.addAll(planPrayers(settings, location, days, now));
    }
    // Вопрос о намазе не зависит от азана: человек может не хотеть звонка
    // ко времени намаза, но хотеть, чтобы у него спросили потом.
    planned.addAll(planAsk(settings, location, tracker, days, now));
    if (planned.isEmpty) return;

    planned.sort((a, b) => a.when.compareTo(b.when));

    // Режим спрашиваем у системы один раз: дальше идут десятки вызовов,
    // и запрашивать разрешение в каждом — это столько же обращений к платформе.
    final mode = await _scheduleMode();
    final take = planned.length > maxPending ? maxPending : planned.length;
    for (var i = 0; i < take; i++) {
      final item = planned[i];
      try {
        await _plugin.zonedSchedule(
          i,
          item.title,
          item.body,
          tz.TZDateTime.from(item.when, tz.local),
          item.details,
          payload: item.payload,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        debugPrint('notification schedule error: $e');
      }
    }
  }

  /// Открыто для теста: именно на стыке этих двух списков жила ошибка,
  /// из-за которой обеты вытесняли напоминания о намазе.
  @visibleForTesting
  static List<PlannedNotification> planPrayers(SettingsService settings,
      AppLocation location, int days, DateTime now) {
    final out = <PlannedNotification>[];
    final prayers = settings.notifyPrayers;
    if (prayers.isEmpty) return out;
    final before = settings.notifyBeforeMinutes;
    for (var d = 0; d < days; d++) {
      final day = now.add(Duration(days: d));
      final times = PrayerService.timesFor(day, location,
          method: settings.method, madhab: settings.madhab);
      for (final k in SettingsService.notifiablePrayers) {
        if (!prayers.contains(k)) continue;
        final when = times[k].subtract(Duration(minutes: before));
        if (!when.isAfter(now)) continue;
        out.add(_prayerPlan(k, when, before));
      }
    }
    return out;
  }

  @visibleForTesting
  static List<PlannedNotification> planZikrs(
      PrivateZikrService svc, int days, DateTime now) {
    final out = <PlannedNotification>[];
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
          out.add(PlannedNotification(
            when: when,
            title: t('Зикр'),
            body: appLang == Lang.ky
                ? '${z.title} — ${left > 0 ? left : z.target} калды'
                : '${z.title} — осталось ${left > 0 ? left : z.target}',
            details: const NotificationDetails(
              android: AndroidNotificationDetails(
                'private_zikr',
                'Закрытые зикры',
                importance: Importance.defaultImportance,
                priority: Priority.defaultPriority,
              ),
              iOS: DarwinNotificationDetails(),
            ),
          ));
        }
      }
    }
    return out;
  }

  /// Вопросы «прочитали ли вы намаз» — через заданную в настройках паузу
  /// после времени намаза, с кнопками «Да» и «Нет» прямо в уведомлении.
  ///
  /// Уже отмеченные намазы пропускаем: спрашивать о том, что человек сам
  /// отметил в приложении, — верный способ приучить его смахивать
  /// уведомления не читая.
  @visibleForTesting
  static List<PlannedNotification> planAsk(SettingsService settings,
      AppLocation location, TrackerService? tracker, int days, DateTime now) {
    final out = <PlannedNotification>[];
    if (!settings.askEnabled) return out;
    final delay = settings.askDelay;
    for (var d = 0; d < days; d++) {
      final day = now.add(Duration(days: d));
      final times = PrayerService.timesFor(day, location,
          method: settings.method, madhab: settings.madhab);
      for (final k in SettingsService.notifiablePrayers) {
        final when = times[k].add(delay);
        if (!when.isAfter(now)) continue;
        if (tracker != null &&
            tracker.statusOf(day, k) != PrayerStatus.pending) {
          continue;
        }
        out.add(_askPlan(k, day, when));
      }
    }
    return out;
  }

  static PlannedNotification _askPlan(
      PrayerKey k, DateTime day, DateTime when) {
    final name = t(k.titleRu);
    final ky = appLang == Lang.ky;
    return PlannedNotification(
      when: when,
      title: ky ? '$name намазын окудуңузбу?' : 'Прочитали ли вы намаз $name?',
      // Подсказка про «потяните вниз» здесь не для красоты: кнопки живут
      // в развёрнутом виде уведомления, и без подсказки человек их не
      // находит — проверено на живом телефоне. Нажатие по самому
      // уведомлению тоже работает: приложение спросит окном.
      body: ky
          ? 'Ылдый тартыңыз — «Ооба» жана «Жок» чыгат.'
          : 'Потяните вниз — появятся «Да» и «Нет».',
      payload: 'ask|${TrackerService.dayKeyOf(day)}|${k.name}',
      details: NotificationDetails(
        android: AndroidNotificationDetails(
          'prayer_ask',
          'Вопрос о намазе',
          channelDescription:
              'Через заданное время спрашивает, прочитан ли намаз',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(_actionYes, t('Да')),
            AndroidNotificationAction(_actionNo, t('Нет')),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: _askCategory,
        ),
      ),
    );
  }

  static PlannedNotification _prayerPlan(PrayerKey k, DateTime when, int before) {
    final name = t(k.titleRu);
    final ky = appLang == Lang.ky;
    return PlannedNotification(
      when: when,
      title: before > 0
          ? (ky ? '$name жакындады' : 'Скоро $name')
          : (ky ? 'Намаз убактысы — $name' : 'Время намаза — $name'),
      body: before > 0
          ? (ky
              ? '$name $before мүнөттөн кийин. Намазга даярданыңыз.'
              : '$name через $before мин. Приготовьтесь к намазу.')
          : (ky
              ? '$name намазынын убактысы кирди. Өткөрүп жибербеңиз.'
              : 'Наступило время намаза $name. Не пропустите.'),
      details: const NotificationDetails(
        // Канал НОВЫЙ, не 'prayer_times'. Звук канала Android задаётся раз
        // и навсегда при его создании: у тех, кто уже пользуется
        // приложением, старый канал так и остался бы со стандартным звуком,
        // и азан они не услышали бы никогда.
        android: AndroidNotificationDetails(
          'prayer_times_azan',
          'Времена намаза',
          channelDescription: 'Напоминания о наступлении времени намаза',
          importance: Importance.max,
          priority: Priority.high,
          sound: RawResourceAndroidNotificationSound('azan'),
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.timeSensitive,
          // Запись лежит в бандле приложения, а не в ресурсах Flutter:
          // звук уведомления система ищет только там. Длительность — 29 с,
          // это потолок iOS; файл длиннее заменяется стандартным звуком.
          sound: _azanSound,
        ),
      ),
    );
  }

  /// Показывает вопрос о намазе через пять секунд — проверка кнопок
  /// «Да»/«Нет».
  ///
  /// Ждать настоящего времени намаза ради этого невозможно, а кнопки живут
  /// в системном слое: тестами их не покрыть, и ломаются они молча. Так уже
  /// было — в изоляте действий не оказалось плагинов, и ответ не доходил
  /// до трекера, а понять это по приложению было нельзя.
  ///
  /// Зовётся из настроек (кнопка «Проверить уведомление») и из отладочного
  /// хука в root_screen.dart.
  static Future<void> showAskDemo(SettingsService settings, PrayerKey k) async {
    await init();
    // Разрешение спрашиваем прямо здесь: иначе на свежем устройстве вопрос
    // просто не покажется, и проверка ничего не проверит.
    await requestPermission();
    final now = DateTime.now();
    final plan = _askPlan(k, now, now.add(const Duration(seconds: 5)));
    await _plugin.zonedSchedule(
      9999,
      plan.title,
      plan.body,
      tz.TZDateTime.from(plan.when, tz.local),
      plan.details,
      payload: plan.payload,
      androidScheduleMode: await _scheduleMode(),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}

/// Запланированное уведомление до отправки в систему. Нужен, чтобы намазы
/// и обеты можно было сложить в один список и отсортировать по времени.
class PlannedNotification {
  final DateTime when;
  final String title;
  final String body;
  final NotificationDetails details;

  /// Для вопроса «прочитали ли вы намаз» — `ask|ГГГГ-ММ-ДД|namaz`.
  /// По ней обработчик кнопок понимает, что и за какой день отмечать.
  final String? payload;
  const PlannedNotification(
      {required this.when,
      required this.title,
      required this.body,
      required this.details,
      this.payload});
}
