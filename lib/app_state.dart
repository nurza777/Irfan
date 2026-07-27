import 'dart:async';

import 'package:flutter/widgets.dart';

import 'services/auth_service.dart';
import 'services/home_widget_service.dart';
import 'services/lang.dart';
import 'services/notification_service.dart';
import 'services/prayer_service.dart';
import 'services/quran_service.dart';
import 'services/settings_service.dart';
import 'services/shop_service.dart';
import 'services/tracker_service.dart';
import 'services/user_registry.dart';
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
  DateTime now = DateTime.now();
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
  Future<Redemption?> redeem(ShopItem item) async {
    if (shop == null || coins < item.cost) return null;
    final r = await shop!.redeem(item);
    notifyListeners();
    return r;
  }

  Future<void> init() async {
    tracker = await TrackerService.create();
    zikrs = await ZikrService.create();
    auth = await AuthService.create();
    settings = await SettingsService.create();
    appLang = settings!.lang; // применить выбранный язык до первого кадра
    quran = await QuranService.create();
    shop = await ShopService.create();
    await HomeWidgetService.init();
    _applyLocationSetting();
    _recompute();
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      now = DateTime.now();
      if (today != null && (now.day != today!.date.day)) {
        _recompute();
        _rescheduleNotifications(); // новый день — обновить окно напоминаний
      }
      notifyListeners();
    });
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
    return UserRegistry.report(u,
        prayersRead: tracker!.totalReadCount(),
        streak: tracker!.currentStreak(),
        coins: coins);
  }

  void _rescheduleNotifications() {
    if (settings == null) return;
    NotificationService.reschedule(settings: settings!, location: location);
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
    required String email,
    required String password,
    required int age,
    required Gender? gender,
  }) async {
    final err = await auth!.register(
        name: name,
        email: email,
        password: password,
        age: age,
        gender: gender);
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
      {required String email, required String password}) async {
    final err = await auth!.login(email: email, password: password);
    if (err == null && auth!.current != null) {
      // Отмечаемся на сервере (профиль + активность) и проверяем блокировку.
      final blocked = await _reportActivity();
      if (blocked == true) {
        await auth!.logout();
        notifyListeners();
        return t('Аккаунт заблокирован администратором');
      }
    }
    notifyListeners();
    return err;
  }

  Future<void> logoutAccount() async {
    await auth!.logout();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
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
