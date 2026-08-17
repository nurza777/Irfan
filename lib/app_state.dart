import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/access_service.dart';
import 'services/certificate_service.dart';
import 'services/account_backup.dart';
import 'services/account_deletion.dart';
import 'services/auth_service.dart';
import 'services/home_widget_service.dart';
import 'services/lang.dart';
import 'services/notification_service.dart';
import 'services/prayer_service.dart';
import 'services/private_zikr_service.dart';
import 'services/quran_service.dart';
import 'services/settings_service.dart';
import 'services/shop_service.dart';
import 'services/tracker_service.dart';
import 'services/wallpaper_service.dart';
import 'services/user_registry.dart';
import 'services/watch_progress.dart';
import 'services/zikr_service.dart';

/// Глобальное состояние: локация, времена намаза на сегодня, трекер,
/// зикры, аккаунт, «сейчас».
class AppState extends ChangeNotifier {
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
    _autoLocation = await PrayerService.resolveLocation();
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
        coins: coins);
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
        privateZikrs: privateZikrs);
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
    }
    await settings!.setNotificationsEnabled(value);
    _rescheduleNotifications();
    notifyListeners();
    return value;
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

  Future<void> markPrayer(PrayerKey key, PrayerStatus status) async {
    await tracker!.setStatus(today!.date, key, status);
    _invalidateCoins();
    notifyListeners();
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
    required int age,
    required Gender? gender,
    String city = '',
  }) async {
    final err = await auth!.register(
        name: name,
        phone: phone,
        password: password,
        age: age,
        gender: gender,
        city: city);
    // Сообщаем профиль на сервер, чтобы админ видел новый аккаунт (без пароля).
    if (err == null && auth!.current != null) {
      await _reportActivity();
    }
    notifyListeners();
    return err;
  }

  Future<void> updateProfile({int? age, Gender? gender}) async {
    await auth!.updateCurrentProfile(age: age, gender: gender);
    notifyListeners();
  }

  Future<String?> loginAccount(
      {required String phone, required String password}) async {
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
      gender: r.gender == 'female' ? Gender.female : Gender.male,
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
