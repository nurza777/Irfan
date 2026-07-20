import 'dart:async';

import 'package:flutter/widgets.dart';

import 'services/prayer_service.dart';
import 'services/tracker_service.dart';

/// Глобальное состояние: локация, времена намаза на сегодня, трекер, «сейчас».
class AppState extends ChangeNotifier {
  AppLocation location = PrayerService.fallbackLocation;
  DayPrayerTimes? today;
  TrackerService? tracker;
  DateTime now = DateTime.now();
  Timer? _ticker;

  bool get ready => today != null && tracker != null;

  Future<void> init() async {
    tracker = await TrackerService.create();
    _recompute();
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      now = DateTime.now();
      if (today != null && (now.day != today!.date.day)) _recompute();
      notifyListeners();
    });
    notifyListeners();
    // Локация — в фоне, чтобы не блокировать первый кадр.
    location = await PrayerService.resolveLocation();
    _recompute();
    notifyListeners();
  }

  void _recompute() {
    now = DateTime.now();
    today = PrayerService.timesFor(now, location);
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
