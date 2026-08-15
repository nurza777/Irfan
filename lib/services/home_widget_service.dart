import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import 'prayer_service.dart';
import 'date_fmt.dart';
import 'lang.dart';

/// Мост к нативному iOS-виджету «Времена намаза» (WidgetKit).
/// Данные кладутся в общий App Group, откуда их читает виджет.
class HomeWidgetService {
  static const _appGroup = 'group.kg.irfan.irfan';
  static const _iOSWidget = 'IrfanWidget';

  static Future<void>? _ready;

  /// Назначение общей группы идёт через системный канал и занимает заметное
  /// время — на симуляторе четверть секунды. Раньше эту четверть секунды ждал
  /// весь экран: `init` стоял в цепочке подготовки перед показом времён
  /// намаза, хотя к виджету на рабочем столе первый кадр приложения никакого
  /// отношения не имеет. Теперь вызов запускается и не ждётся, а [update]
  /// сам дожидается готовности перед записью — виджет по-прежнему получает
  /// данные с первого же пересчёта.
  static Future<void> init() => _ready ??= _init();

  static Future<void> _init() async {
    try {
      await HomeWidget.setAppGroupId(_appGroup);
    } catch (e) {
      debugPrint('home widget init error: $e');
    }
  }

  /// Записывает времена намаза текущего дня и обновляет виджет.
  static Future<void> update(DayPrayerTimes times, String city) async {
    try {
      await init();
      final hhmm = DateFormat('HH:mm');
      await HomeWidget.saveWidgetData<String>('city', city);
      await HomeWidget.saveWidgetData<String>(
          'date', fmtDayMonth(times.date));
      for (final k in PrayerKey.values) {
        await HomeWidget.saveWidgetData<String>(
            '${k.name}_label', t(k.titleRu));
        await HomeWidget.saveWidgetData<String>(
            '${k.name}_time', hhmm.format(times[k]));
        // Секунды от полуночи — чтобы виджет подсветил ближайший намаз.
        final at = times[k];
        await HomeWidget.saveWidgetData<int>(
            '${k.name}_mins', at.hour * 60 + at.minute);
      }
      await HomeWidget.updateWidget(iOSName: _iOSWidget);
    } catch (e) {
      debugPrint('home widget update error: $e');
    }
  }
}
