import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/access_service.dart';
import 'services/books_service.dart';
import 'services/certificate_service.dart';
import 'services/account_backup.dart';
import 'services/account_deletion.dart';
import 'services/auth_service.dart';
import 'services/home_widget_service.dart';
import 'services/lang.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
import 'services/prayer_service.dart';
import 'services/private_zikr_service.dart';
import 'services/quran_service.dart';
import 'services/settings_service.dart';
import 'services/shop_service.dart';
import 'services/support_chat_service.dart';
import 'services/tracker_service.dart';
import 'services/wallpaper_service.dart';
import 'services/user_registry.dart';
import 'services/watch_progress.dart';
import 'services/zikr_service.dart';

/// Глобальное состояние: локация, времена намаза на сегодня, трекер,
/// зикры, аккаунт, «сейчас».
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppLocation location = PrayerService.fallbackLocation;
  DayPrayerTimes? today;
  TrackerService? tracker;
  ZikrService? zikrs;
  AuthService? auth;
  SettingsService? settings;
  QuranService? quran;
  ShopService? shop;
  PrivateZikrService? privateZikrs;
  DateTime now = DateTime.now();

  /// Секундные часы — отдельно от состояния.
  ///
  /// На [AppState] подписаны полтора десятка экранов, а обратный отсчёт нужен
  /// двум. Слушать время через них значило бы перестраивать каждую секунду
  /// весь Коран, настройки и магазин; поэтому тик идёт сюда, а экраны берут
  /// его через `ValueListenableBuilder`.
  final ValueNotifier<DateTime> clock = ValueNotifier(DateTime.now());

  Timer? _ticker;

  /// Локация, найденная геолокацией (для режима «автоматически»).
  AppLocation? _autoLocation;

  bool get ready => today != null && tracker != null;

  /// Сегодняшняя дата без времени — ключ для трекера и зикров.
  DateTime get todayDate => DateTime(now.year, now.month, now.day);

  // --- Коины: 1 намаз (прочитан) = 5, каждые 33 повтора зикра = 1 ---
  /// Потолок кошелька — заработать можно максимум 1000 коинов.
  static const maxCoins = 1000;

  // Кэш: сканирование хранилища дорогое, а главный экран перерисовывается
  // раз в секунду. Сбрасывается при изменении данных ([_invalidateCoins]).
  int? _prayerCoinsCache;
  int? _zikrCoinsCache;
  void _invalidateCoins() {
    _prayerCoinsCache = null;
    _zikrCoinsCache = null;
  }

  int get prayerCoins =>
      _prayerCoinsCache ??= (tracker?.totalReadCount() ?? 0) * 5;
  int get zikrCoins => _zikrCoinsCache ??= (zikrs?.totalCoins() ?? 0);

  /// Всего заработано (с потолком 1000).
  int get earnedCoins => (prayerCoins + zikrCoins).clamp(0, maxCoins);
  int get spentCoins => shop?.spent ?? 0;

  /// Доступный баланс = заработано − потрачено.
  int get coins => (earnedCoins - spentCoins).clamp(0, maxCoins);

  /// Выкуп награды. Возвращает запись при успехе, иначе null (мало коинов).
  /// Обмен коинов. Баланс проверяет и код выдаёт сервер — локальная проверка
  /// ниже нужна лишь чтобы не ходить в сеть с заведомо пустым балансом.
  Future<RedeemResult> redeem(ShopItem item) async {
    final phone = auth?.current?.phone;
    if (shop == null || phone == null) return RedeemResult.error();
    if (coins < item.cost) return RedeemResult.notEnough(coins);
    final r = await shop!.redeem(item, phone);
    notifyListeners();
    return r;
  }

  Future<void> init() async {
    final startedAt = DateTime.now();
    tracker = await TrackerService.create();
    zikrs = await ZikrService.create();
    auth = await AuthService.create();
    settings = await SettingsService.create();
    appLang = settings!.lang; // применить выбранный язык до первого кадра
    quran = await QuranService.create();
    shop = await ShopService.create();
    privateZikrs = await PrivateZikrService.create();
    // Запускаем, но не ждём: см. HomeWidgetService.init.
    unawaited(HomeWidgetService.init());
    await WallpaperService.instance.init();
    await CertificateService.instance.init();
    await WatchProgress.instance.init();
    _applyLocationSetting();
    _recompute();
    // Ответ на вопрос о намазе может прийти из уведомления, пока приложение
    // открыто: тогда запись делает другой обработчик, и состояние в памяти
    // о ней не знает — перечитываем хранилище и перерисовываемся.
    // Пока приложение было в фоне, человек мог ответить прямо в уведомлении —
    // запись сделал другой изолят, и в памяти лежат устаревшие значения.
    WidgetsBinding.instance.addObserver(this);
    NotificationService.onAnswered = () async {
      await tracker?.reload();
      _invalidateCoins();
      notifyListeners();
      _rescheduleNotifications();
    };
    // Токен APNs меняется сам по себе — после переустановки, восстановления
    // из копии, долгого простоя. Обновляем его при каждом запуске, иначе
    // сервер продолжал бы слать на мёртвый адрес.
    if (settings?.liveNotificationsEnabled == true) {
      unawaited(PushService.enable());
    } else {
      // Уведомления уже разрешены (например, раньше включали азан), а эфир
      // человек сам не выключал — включаем его по умолчанию.
      unawaited(_adoptLiveDefaultIfPermitted());
    }
    // Ответ поддержки мог прийти, пока приложение было закрыто.
    unawaited(SupportChatService.refreshUnread(auth?.current?.phone));
    // Есть ли книги — от этого зависит, показывать ли пункт «Книги» в меню.
    unawaited(BooksService.instance.refreshAvailability());
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final prev = now;
      now = DateTime.now();
      if (today != null && (now.day != today!.date.day)) {
        _recompute();
        _rescheduleNotifications(); // новый день — обновить окно напоминаний
        notifyListeners();
      } else if (now.minute != prev.minute) {
        // Раз в минуту — чтобы не застывали подсветка текущего намаза и
        // вопрос «прочитали ли вы намаз»: с точностью до минуты этого
        // достаточно, а рисуется в 60 раз реже.
        notifyListeners();
      }
      // Секундная стрелка идёт ОТДЕЛЬНЫМ уведомлением. Раньше здесь стоял
      // notifyListeners() на каждый тик, и раз в секунду перестраивались все
      // экраны под AppScope — включая Коран, настройки и магазин, которым
      // время вообще не нужно. Обратный отсчёт слушает [clock] сам.
      clock.value = now;
    });
    if (kDebugMode) {
      // Сколько прошло от начала подготовки до кадра, на котором человек
      // видит времена намаза. Меряется, а не оценивается на глаз.
      debugPrint('STARTUP init->первый экран: '
          '${DateTime.now().difference(startedAt).inMilliseconds} мс');
    }
    notifyListeners();
    // Локация — в фоне, чтобы не блокировать первый кадр.
    //
    // И только если город НЕ выбран вручную. Раньше геопозицию спрашивали
    // всегда: человек указывал город руками, а система всё равно показывала
    // окно «разрешить доступ к геопозиции» — просьба о разрешении, которое
    // приложению в этот момент не нужно. Для App Store это лишний вопрос
    // на проверке, а для человека — повод отказать не глядя.
    if (settings?.locationMode != LocationMode.manual) {
      _autoLocation = await PrayerService.resolveLocation();
    }
    _applyLocationSetting();
    _recompute();
    notifyListeners();
    // Переставить напоминания о намазе под актуальную локацию/время.
    _rescheduleNotifications();
    // Обновить активность на сервере (для дашборда устаза), если есть аккаунт.
    _reportActivity();
  }

  /// Отправляет профиль + активность (намазы/серия/коины) на сервер.
  /// Возвращает статус блокировки (для проверки при входе).
  Future<bool?> _reportActivity() async {
    final u = auth?.current;
    if (u == null || tracker == null) return null;
    final blocked = await UserRegistry.report(u,
        prayersRead: tracker!.totalReadCount(),
        streak: tracker!.currentStreak(),
        coins: coins,
        // Очки соревнования считаем БЕЗ потолка и без вычета трат:
        // в таблице человек не должен опускаться за то, что потратил
        // заработанное. См. UserRegistry.report.
        score: prayerCoins + zikrCoins,
        hideInRating: settings?.hideInRating);
    // Слепок для переноса на другой телефон — после отчёта: сервер должен
    // сначала завести запись, иначе класть слепок будет не к чему.
    // Сам класс решает, изменилось ли что-нибудь и не слишком ли часто.
    if (blocked != true) unawaited(AccountBackup.maybeUpload(u.phone));
    return blocked;
  }

  void _rescheduleNotifications() {
    if (settings == null) return;
    NotificationService.reschedule(
        settings: settings!,
        location: location,
        privateZikrs: privateZikrs,
        tracker: tracker);
  }

  /// Перепланировать напоминания извне (например, после правки обета).
  Future<void> rescheduleNotifications() async {
    _rescheduleNotifications();
  }

  /// Включить/выключить напоминания о намазе. При включении спрашивает
  /// системное разрешение; возвращает итоговое состояние (false — если
  /// разрешение не выдано).
  Future<bool> setNotificationsEnabled(bool value) async {
    if (value) {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        await settings!.setNotificationsEnabled(false);
        notifyListeners();
        return false;
      }
      await _adoptLiveDefault(granted);
    }
    await settings!.setNotificationsEnabled(value);
    _rescheduleNotifications();
    notifyListeners();
    return value;
  }

  /// Включить/выключить уведомления о начале эфира. Разрешение то же самое,
  /// что и для азана, поэтому спрашиваем его так же; отличие в том, что
  /// после согласия нужно ещё подписаться на APNs и отдать токен серверу.
  Future<bool> setLiveNotificationsEnabled(bool value) async {
    if (value) {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        // «Выключено» НЕ записываем: это не решение человека, а отказ
        // системы. Разрешит позже в настройках телефона — эфир включится
        // сам (см. _adoptLiveDefaultIfPermitted), как он и хотел.
        notifyListeners();
        return false;
      }
      await PushService.enable();
    }
    await settings!.setLiveNotificationsEnabled(value);
    notifyListeners();
    return value;
  }

  /// Уведомления разрешили — включаем эфир, если человек его сам не трогал.
  Future<void> _adoptLiveDefault(bool granted) async {
    final s = settings;
    if (s == null) return;
    // Пуши об эфире сейчас приходят только на iOS (на Android нужен FCM).
    if (await s.adoptLiveDefault(granted: granted, supported: Platform.isIOS)) {
      unawaited(PushService.enable());
      notifyListeners();
    }
  }

  /// То же при запуске и возврате в приложение: без окна с вопросом, только
  /// по уже выданному разрешению.
  Future<void> _adoptLiveDefaultIfPermitted() async {
    final s = settings;
    if (s == null || s.liveNotificationsChosen || !Platform.isIOS) return;
    await _adoptLiveDefault(await NotificationService.hasPermission());
  }

  /// Спрашивать ли после намаза «прочитали?». Разрешение то же, что у азана.
  Future<bool> setAskEnabled(bool value) async {
    if (value) {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        await settings!.setAskEnabled(false);
        notifyListeners();
        return false;
      }
      await _adoptLiveDefault(granted);
    }
    await settings!.setAskEnabled(value);
    _rescheduleNotifications();
    notifyListeners();
    return value;
  }

  Future<void> setAskDelayMinutes(int minutes) async {
    await settings!.setAskDelayMinutes(minutes);
    _rescheduleNotifications();
    notifyListeners();
  }

  Future<void> setNotifyBeforeMinutes(int minutes) async {
    await settings!.setNotifyBeforeMinutes(minutes);
    _rescheduleNotifications();
    notifyListeners();
  }

  Future<void> setNotifyPrayers(Set<PrayerKey> prayers) async {
    await settings!.setNotifyPrayers(prayers);
    _rescheduleNotifications();
    notifyListeners();
  }

  /// Прятать ли себя из общей таблицы соревнования. Сразу отправляем
  /// на сервер: иначе человек снял бы галочку и остался в таблице до
  /// следующего запуска приложения.
  Future<void> setHideInRating(bool v) async {
    await settings!.setHideInRating(v);
    notifyListeners();
    unawaited(_reportActivity());
  }

  /// Показывает проверочный вопрос о намазе через пять секунд.
  ///
  /// Нужен потому, что кнопки «Да»/«Нет» живут в системном слое: их не
  /// покрыть тестами, а сломаться они могут молча — так и случилось, когда
  /// в изоляте действий не оказалось плагинов, и ответ не доходил до
  /// трекера. Проверка занимает полминуты вместо ожидания времени намаза.
  Future<void> sendAskTest() =>
      NotificationService.showAskDemo(settings!, PrayerKey.fajr);

  Future<void> setLanguage(Lang l) async {
    await settings!.setLang(l);
    appLang = l;
    notifyListeners();
  }

  void _applyLocationSetting() {
    final s = settings!;
    location = s.locationMode == LocationMode.manual
        ? s.manualCity.location
        : (_autoLocation ?? PrayerService.fallbackLocation);
  }

  void _recompute() {
    now = DateTime.now();
    today = PrayerService.timesFor(now, location,
        method: settings?.method ?? CalcMethod.muslimWorldLeague,
        madhab: settings?.madhab ?? AsrMadhab.hanafi);
    HomeWidgetService.update(today!, location.cityName);
  }

  /// Следующий намаз и время до него: сегодня или завтрашний Фаджр.
  (PrayerKey, DateTime) nextPrayer() {
    final t = today!;
    final k = t.nextAfter(now);
    if (k != null) return (k, t[k]);
    final tomorrow =
        PrayerService.timesFor(now.add(const Duration(days: 1)), location);
    return (PrayerKey.fajr, tomorrow[PrayerKey.fajr]);
  }

  /// Меняет отметку намаза за ЛЮБОЙ день — им пользуется экран
  /// восстановления пропущенных. [markPrayer] пишет только сегодняшний день
  /// и потому здесь не подходит.
  Future<void> setPrayerStatusOn(
      DateTime day, PrayerKey key, PrayerStatus status) async {
    await tracker!.setStatus(day, key, status);
    _invalidateCoins();
    notifyListeners();
    // Уведомления пересобираем только если тронули сегодняшний день: за
    // прошлые дни ничего не запланировано, а перепланирование шестидесяти
    // уведомлений на каждое нажатие в длинном списке — заметная задержка.
    final t = today;
    if (t != null &&
        TrackerService.dayKeyOf(day) == TrackerService.dayKeyOf(t.date)) {
      _rescheduleNotifications();
    }
    final phone = auth?.current?.phone;
    if (phone != null) unawaited(AccountBackup.maybeUpload(phone));
  }

  Future<void> markPrayer(PrayerKey key, PrayerStatus status) async {
    await tracker!.setStatus(today!.date, key, status);
    _invalidateCoins();
    notifyListeners();
    // Пересобираем уведомления: вопрос об этом намазе больше не нужен,
    // а он уже стоит в очереди системы.
    _rescheduleNotifications();
    // Отметка намаза — то самое, что обиднее всего терять вместе с телефоном.
    // Слепок уходит не чаще раза в четверть часа, см. AccountBackup.
    final phone = auth?.current?.phone;
    if (phone != null) unawaited(AccountBackup.maybeUpload(phone));
  }

  // --- Зикры ---

  Future<void> incrementZikr(String id) async {
    await zikrs!.increment(todayDate, id);
    _invalidateCoins();
    notifyListeners();
  }

  Future<void> resetZikr(String id) async {
    await zikrs!.reset(todayDate, id);
    _invalidateCoins();
    notifyListeners();
  }

  Future<void> saveZikrGoals(List<ZikrGoal> goals) async {
    await zikrs!.saveGoals(goals);
    _invalidateCoins();
    notifyListeners();
  }

  // --- Настройки ---

  Future<void> setLocationMode(LocationMode m) async {
    await settings!.setLocationMode(m);
    _applyLocationSetting();
    _recompute();
    notifyListeners();
    _rescheduleNotifications();
    // В авто-режиме уточняем позицию в фоне, если её ещё нет.
    if (m == LocationMode.auto && _autoLocation == null) {
      _autoLocation = await PrayerService.resolveLocation();
      _applyLocationSetting();
      _recompute();
      _rescheduleNotifications();
      notifyListeners();
    }
  }

  Future<void> setManualCity(City c) async {
    await settings!.setManualCity(c);
    _applyLocationSetting();
    _recompute();
    _rescheduleNotifications();
    notifyListeners();
  }

  Future<void> setMadhab(AsrMadhab m) async {
    await settings!.setMadhab(m);
    _recompute();
    _rescheduleNotifications();
    notifyListeners();
  }

  Future<void> setCalcMethod(CalcMethod m) async {
    await settings!.setMethod(m);
    _recompute();
    notifyListeners();
  }

  // --- Аккаунт ---

  Future<String?> registerAccount({
    required String name,
    required String phone,
    required String password,
    required DateTime? birthDate,
    required Gender? gender,
    String city = '',
  }) async {
    final err = await auth!.register(
        name: name,
        phone: phone,
        password: password,
        birthDate: birthDate,
        gender: gender,
        city: city);
    // Сообщаем профиль на сервер, чтобы админ видел новый аккаунт (без пароля).
    if (err == null && auth!.current != null) {
      await _reportActivity();
    }
    notifyListeners();
    return err;
  }

  Future<void> updateProfile({DateTime? birthDate, Gender? gender}) async {
    await auth!.updateCurrentProfile(birthDate: birthDate, gender: gender);
    notifyListeners();
  }

  /// Вход по номеру и паролю.
  ///
  /// Аккаунт живёт на телефоне, но человек мог прийти с другого — купил
  /// новый, переустановил систему, потерял прежний. Тогда локальной записи
  /// нет, и аккаунт забирается с сервера тем же паролем.
  ///
  /// Раньше для этого надо было отдельно открыть «Восстановить аккаунт» и
  /// ждать кода, который устаз называет вручную: автоотправки нет, и человек
  /// упирался в ожидание. Теперь вход — один и тот же путь везде.
  Future<String?> loginAccount(
      {required String phone, required String password}) async {
    if (!auth!.hasLocal(phone)) {
      final err = await _signInFromServer(phone: phone, password: password);
      notifyListeners();
      return err;
    }
    final err = await auth!.login(phone: phone, password: password);
    if (err == null && auth!.current != null) {
      // Отмечаемся на сервере (профиль + активность) и проверяем блокировку.
      final blocked = await _reportActivity();
      if (blocked == true) {
        await auth!.logout();
        AccessService.instance.clear();
        CertificateService.instance.clear();
        notifyListeners();
        return t('Аккаунт заблокирован администратором');
      }
    }
    notifyListeners();
    return err;
  }

  /// Забирает аккаунт с сервера по номеру и паролю и входит в него.
  /// null — успех, иначе текст ошибки.
  Future<String?> _signInFromServer(
      {required String phone, required String password}) async {
    final ph = normalizePhone(phone);
    if (ph.isEmpty) return t('Некорректный номер телефона');
    if (password.length < 6) return t('Пароль — минимум 6 символов');
    // Доказательство считается из пароля и номера — то же самое значение,
    // что телефон-владелец уже прислал серверу. Сам пароль никуда не идёт.
    final proof = await AuthService.makeProof(ph, password);
    final r = await AccountRestore.fetch(ph, pass: proof);
    return switch (r.status) {
      RestoreStatus.ok =>
        await restoreAccount(r, phone: ph, password: password),
      RestoreStatus.notFound => t('Аккаунт не найден'),
      RestoreStatus.badPassword => t('Неверный пароль'),
      RestoreStatus.blocked => t('Аккаунт заблокирован администратором'),
      // Сервер не принял ни пароль, ни разрешение. Случай редкий: запись
      // закрыта паролем, а приложение его не отправило.
      RestoreStatus.needsCode =>
        t('Не удалось войти — обратитесь в поддержку'),
      RestoreStatus.offline => t('Нет связи с сервером — попробуйте позже'),
      RestoreStatus.error => t('Не удалось войти'),
    };
  }

  /// Переносит аккаунт на это устройство: кладёт слепок в хранилище, заводит
  /// локальную запись и пересобирает сервисы. null — успех, иначе текст ошибки.
  ///
  /// Пароль задаётся заново и намеренно: на сервере его нет и никогда не было,
  /// он запирает аккаунт только на этом телефоне.
  Future<String?> restoreAccount(
    RestoreResult r, {
    required String phone,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // Слепок — до создания записи: иначе первый же _reportActivity ушёл бы на
    // сервер с пустой историей и обнулил бы там серию и коины.
    await AccountBackup.apply(prefs, r.data ?? const {}, serverSpent: r.spent);
    final err = await auth!.restore(
      name: r.name,
      phone: phone,
      password: password,
      createdAt: r.createdAt ?? DateTime.now(),
      age: r.age,
      birthDate: r.birthDate,
      // Пол теперь необязателен: пустое значение НЕ превращаем в мужской,
      // иначе перенос аккаунта дописывал бы человеку то, чего он не указывал.
      gender: r.gender == 'female'
          ? Gender.female
          : (r.gender == 'male' ? Gender.male : null),
      city: r.city,
    );
    if (err != null) return err;
    // Те же пересоздания, что и после удаления аккаунта: коины, серии и
    // счётчики считаются из истории, а она только что стала другой.
    tracker = await TrackerService.create();
    zikrs = await ZikrService.create();
    privateZikrs = await PrivateZikrService.create();
    shop = await ShopService.create();
    quran = await QuranService.create();
    settings = await SettingsService.create();
    appLang = settings!.lang;
    _invalidateCoins();
    _applyLocationSetting();
    _recompute();
    _rescheduleNotifications();
    // Метки прошлого слепка не наши — иначе первый настоящий слепок с этого
    // телефона ушёл бы только через сутки.
    await AccountBackup.forgetMarks();
    await _reportActivity();
    notifyListeners();
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _refreshAfterBackground();
  }

  Future<void> _refreshAfterBackground() async {
    await tracker?.reload();
    _recompute();
    _invalidateCoins();
    notifyListeners();
    // Отметки могли измениться — значит и набор вопросов другой.
    _rescheduleNotifications();
    // Пока телефон лежал в кармане, админ мог выдать доступ к курсам.
    // Без этого запроса человек узнавал бы о нём только после того, как
    // выгрузит приложение из памяти и запустит заново, — а он этого,
    // разумеется, не делает и считает, что доступ не выдали.
    unawaited(_reportActivity());
    unawaited(SupportChatService.refreshUnread(auth?.current?.phone));
    // Уведомления могли разрешить в настройках телефона, пока нас не было.
    unawaited(_adoptLiveDefaultIfPermitted());
  }

  /// Перезапрашивает профиль и доступы у сервера.
  ///
  /// Открыто для экранов: страница курсов зовёт это при каждом обновлении,
  /// чтобы свежевыданный доступ появлялся по кнопке, а не после перезапуска.
  Future<void> refreshAccess() => _reportActivity();

  Future<void> logoutAccount() async {
    await auth!.logout();
    // Иначе следующий ученик на этом же устройстве увидел бы курсы,
    // открытые предыдущему, — пока сервер не ответит по нему самому.
    AccessService.instance.clear();
    CertificateService.instance.clear();
    notifyListeners();
  }

  /// Удаляет аккаунт и все данные человека. null — успех, иначе текст ошибки
  /// (при ошибке данные остаются нетронутыми, см. [AccountDeletion]).
  Future<String?> deleteAccount() async {
    final err = await AccountDeletion.deleteCurrent(auth!);
    if (err != null) return err;
    AccessService.instance.clear();
    CertificateService.instance.clear();
    // Пересоздаём сервисы: коины, стрики и счётчики зикров считаются из
    // истории, а она только что стёрта — иначе на экране остались бы
    // цифры удалённого аккаунта до перезапуска приложения.
    auth = await AuthService.create();
    tracker = await TrackerService.create();
    zikrs = await ZikrService.create();
    privateZikrs = await PrivateZikrService.create();
    shop = await ShopService.create();
    // Без сброса кэша чип на главном показывал бы коины удалённого аккаунта.
    _invalidateCoins();
    notifyListeners();
    return null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.onAnswered = null;
    _ticker?.cancel();
    clock.dispose();
    super.dispose();
  }
}

/// Доступ к [AppState] по контексту: `AppScope.of(context)`.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
