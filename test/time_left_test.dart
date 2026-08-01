import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/date_fmt.dart';
import 'package:irfan/services/lang.dart';

/// Срок доступа к курсу ученик читает чаще, чем дату окончания, поэтому
/// формулировки проверяем отдельно — на числительных легко ошибиться.
void main() {
  final now = DateTime(2026, 8, 1, 12, 0);

  setUp(() => appLang = Lang.ru);

  test('дни склоняются по-русски', () {
    expect(timeLeftText(now.add(const Duration(days: 21)), now: now),
        'Осталось 21 день');
    expect(timeLeftText(now.add(const Duration(days: 22)), now: now),
        'Осталось 22 дня');
    expect(timeLeftText(now.add(const Duration(days: 25)), now: now),
        'Осталось 25 дней');
    // 11–14 — исключение: «одиннадцать дней», а не «день».
    expect(timeLeftText(now.add(const Duration(days: 11)), now: now),
        'Осталось 11 дней');
  });

  test('последний день назван словами, а не «1 день»', () {
    expect(timeLeftText(now.add(const Duration(days: 1, hours: 2)), now: now),
        'Остался последний день');
  });

  test('меньше суток — часы, меньше часа — минуты', () {
    expect(timeLeftText(now.add(const Duration(hours: 5)), now: now),
        'Осталось 5 часов');
    expect(timeLeftText(now.add(const Duration(hours: 2)), now: now),
        'Осталось 2 часа');
    expect(timeLeftText(now.add(const Duration(minutes: 20)), now: now),
        'Осталось 20 мин');
  });

  test('истёкший срок не показывает отрицательных чисел', () {
    expect(timeLeftText(now.subtract(const Duration(days: 3)), now: now),
        'Срок истёк');
  });

  test('кыргызский вариант отличается от русского', () {
    appLang = Lang.ky;
    expect(timeLeftText(now.add(const Duration(days: 25)), now: now),
        '25 күн калды');
    expect(timeLeftText(now.subtract(const Duration(days: 1)), now: now),
        'Мөөнөтү бүттү');
  });
}
