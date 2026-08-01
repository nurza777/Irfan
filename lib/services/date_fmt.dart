/// Форматирование дат с учётом языка приложения.
///
/// В `intl` нет кыргызской локали, поэтому кыргызские даты собираются вручную.
/// Отличие от русского не только в словах: в кыргызском число пишется с
/// дефисом и месяц стоит в именительном падеже — «27-июль, 2026»
/// (в русском — «27 июля 2026»).
library;

import 'package:intl/intl.dart';

import 'lang.dart';

/// Месяцы (именительный падеж — так они и стоят в кыргызской дате).
const kyMonths = [
  'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
  'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
];

const kyMonthsShort = [
  'янв', 'фев', 'мар', 'апр', 'май', 'июн',
  'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
];

/// Дни недели, DateTime.weekday: 1 = понедельник.
const kyWeekdays = [
  'дүйшөмбү', 'шейшемби', 'шаршемби', 'бейшемби',
  'жума', 'ишемби', 'жекшемби',
];

const kyWeekdaysShort = ['Дү', 'Ше', 'Ша', 'Бе', 'Жу', 'Иш', 'Же'];

/// «27-июль, 2026» / «27 июля 2026».
String fmtDateLong(DateTime d) => appLang == Lang.ky
    ? '${d.day}-${kyMonths[d.month - 1]}, ${d.year}'
    : DateFormat('d MMMM yyyy', 'ru').format(d);

/// «27-июл, 2026» / «27 июл 2026».
String fmtDateShort(DateTime d) => appLang == Lang.ky
    ? '${d.day}-${kyMonthsShort[d.month - 1]}, ${d.year}'
    : DateFormat('d MMM yyyy', 'ru').format(d);

/// «27-июль, дүйшөмбү» / «27 июля, понедельник».
String fmtDayWeekday(DateTime d) => appLang == Lang.ky
    ? '${d.day}-${kyMonths[d.month - 1]}, ${kyWeekdays[d.weekday - 1]}'
    : DateFormat('d MMMM, EEEE', 'ru').format(d);

/// «27-июль» / «27 июля» — без года (виджет на экране «Домой»).
String fmtDayMonth(DateTime d) => appLang == Lang.ky
    ? '${d.day}-${kyMonths[d.month - 1]}'
    : DateFormat('d MMMM', 'ru').format(d);

/// «Дү» / «Пн» — колонки недельной сетки трекера.
String fmtWeekdayShort(DateTime d) => appLang == Lang.ky
    ? kyWeekdaysShort[d.weekday - 1]
    : DateFormat('E', 'ru').format(d);

/// «день / дня / дней» — русские числительные при склонении по числу.
String daysWord(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'день';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня';
  return 'дней';
}

/// Сколько осталось до [until]: «Осталось 12 дней», «Остался последний день»,
/// «Осталось 3 часа». Ученику важнее срок, чем календарная дата — по дате он
/// всё равно считает в уме, сколько у него ещё есть.
String timeLeftText(DateTime until, {DateTime? now}) {
  final left = until.difference(now ?? DateTime.now());
  if (left.isNegative) {
    return appLang == Lang.ky ? 'Мөөнөтү бүттү' : 'Срок истёк';
  }
  if (left.inHours < 1) {
    final m = left.inMinutes.clamp(1, 59);
    return appLang == Lang.ky ? '$m мүнөт калды' : 'Осталось $m мин';
  }
  if (left.inDays < 1) {
    final h = left.inHours;
    return appLang == Lang.ky
        ? '$h саат калды'
        : 'Осталось $h ${h == 1 ? 'час' : (h < 5 ? 'часа' : 'часов')}';
  }
  final d = left.inDays;
  if (d == 1) {
    return appLang == Lang.ky ? 'Акыркы күн калды' : 'Остался последний день';
  }
  return appLang == Lang.ky ? '$d күн калды' : 'Осталось $d ${daysWord(d)}';
}
