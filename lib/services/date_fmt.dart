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
