import 'package:adhan_dart/adhan_dart.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

import 'lang.dart';
import 'settings_service.dart';

/// Ключи намазов в порядке дня. «sunrise» — не намаз, но показывается в списке.
enum PrayerKey { fajr, sunrise, dhuhr, asr, maghrib, isha }

extension PrayerKeyX on PrayerKey {
  String get titleRu => switch (this) {
        PrayerKey.fajr => 'Фаджр',
        PrayerKey.sunrise => 'Восход',
        PrayerKey.dhuhr => 'Зухр',
        PrayerKey.asr => 'Аср',
        PrayerKey.maghrib => 'Магриб',
        PrayerKey.isha => 'Иша',
      };

  /// Восход — не намаз, по нему трекер не спрашивает.
  bool get isPrayer => this != PrayerKey.sunrise;
}

class DayPrayerTimes {
  final DateTime date;
  final Map<PrayerKey, DateTime> times;
  DayPrayerTimes(this.date, this.times);

  DateTime operator [](PrayerKey k) => times[k]!;

  /// Ближайший следующий намаз (или восход) после [now]; null — все прошли.
  PrayerKey? nextAfter(DateTime now) {
    for (final k in PrayerKey.values) {
      if (times[k]!.isAfter(now)) return k;
    }
    return null;
  }

  /// Текущий «активный» намаз — последний, чьё время уже наступило.
  PrayerKey? currentAt(DateTime now) {
    PrayerKey? current;
    for (final k in PrayerKey.values) {
      if (!times[k]!.isAfter(now)) current = k;
    }
    return current;
  }
}

class AppLocation {
  final double latitude;
  final double longitude;
  final String cityName;
  final bool isFallback;
  const AppLocation(this.latitude, this.longitude, this.cityName,
      {this.isFallback = false});
}

class PrayerService {
  /// Бишкек — фолбэк, пока нет геолокации.
  static const AppLocation fallbackLocation =
      AppLocation(42.8746, 74.5698, 'Бишкек', isFallback: true);

  /// Параметры расчёта из настроек; по умолчанию — Всемирная мусульманская
  /// лига + ханафитский мазхаб (для КР).
  static CalculationParameters _params(
      CalcMethod method, AsrMadhab madhab) {
    final p = switch (method) {
      CalcMethod.muslimWorldLeague =>
        CalculationMethodParameters.muslimWorldLeague(),
      CalcMethod.russia => CalculationMethodParameters.russia(),
      CalcMethod.ummAlQura => CalculationMethodParameters.ummAlQura(),
      CalcMethod.egyptian => CalculationMethodParameters.egyptian(),
      CalcMethod.karachi => CalculationMethodParameters.karachi(),
      CalcMethod.turkiye => CalculationMethodParameters.turkiye(),
      CalcMethod.northAmerica =>
        CalculationMethodParameters.northAmerica(),
    };
    p.madhab =
        madhab == AsrMadhab.hanafi ? Madhab.hanafi : Madhab.shafi;
    p.highLatitudeRule = HighLatitudeRule.twilightAngle;
    return p;
  }

  static DayPrayerTimes timesFor(DateTime day, AppLocation loc,
      {CalcMethod method = CalcMethod.muslimWorldLeague,
      AsrMadhab madhab = AsrMadhab.hanafi}) {
    final coordinates = Coordinates(loc.latitude, loc.longitude);
    final pt = PrayerTimes(
      date: DateTime(day.year, day.month, day.day, 12),
      coordinates: coordinates,
      calculationParameters: _params(method, madhab),
      precision: true,
    );
    DateTime local(DateTime utc) {
      final l = utc.toLocal();
      return DateTime(l.year, l.month, l.day, l.hour, l.minute, l.second);
    }

    return DayPrayerTimes(day, {
      PrayerKey.fajr: local(pt.fajr),
      PrayerKey.sunrise: local(pt.sunrise),
      PrayerKey.dhuhr: local(pt.dhuhr),
      PrayerKey.asr: local(pt.asr),
      PrayerKey.maghrib: local(pt.maghrib),
      PrayerKey.isha: local(pt.isha),
    });
  }

  /// Запрашивает разрешение и возвращает позицию; при отказе — Бишкек.
  static Future<AppLocation> resolveLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return fallbackLocation;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return fallbackLocation;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 15));

      String city = t('Моё место');
      try {
        final placemarks = await geocoding.Geocoding()
            .placemarkFromCoordinates(pos.latitude, pos.longitude,
                locale: const Locale('ru'));
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          city = p.locality?.isNotEmpty == true
              ? p.locality!
              : (p.administrativeArea ?? city);
        }
      } catch (_) {}

      return AppLocation(pos.latitude, pos.longitude, city);
    } catch (_) {
      return fallbackLocation;
    }
  }
}
