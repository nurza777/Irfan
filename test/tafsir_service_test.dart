import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/tafsir_service.dart';

/// Толкование у azan.ru **групповое**: один текст объясняет несколько аятов
/// подряд. Проверяется именно это — что аят из середины группы находит свой
/// текст. Ошибка здесь не упала бы, а тихо показывала бы «толкования нет» на
/// двух третях аятов, потому что при точном совпадении номера находится
/// только первый аят каждой группы.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tafsir = TafsirService.instance;

  test('аят с собственным толкованием находится', () async {
    final e = await tafsir.forVerse(2, 255);   // аят аль-Курси
    expect(e, isNotNull);
    expect(e!.hasText, isTrue);
    expect(e.from <= 255 && 255 <= e.to, isTrue);
    expect(e.text, contains('аль-Курси'));
    expect(e.sourceUrl, 'https://azan.ru/tafsir/al-Bakara');
  });

  test('аят из середины группы получает текст группы', () async {
    // Сура «аль-Адият»: один текст на аяты 1–5, следующий на 6–10.
    final first = await tafsir.forVerse(100, 1);
    final middle = await tafsir.forVerse(100, 3);
    expect(first, isNotNull);
    expect(middle, isNotNull);
    expect(middle!.text, first!.text);
    expect(middle.from, 1);
    expect(middle.to, greaterThanOrEqualTo(3));
    expect(middle.rangeLabel, contains('–'));
  });

  test('у каждой суры есть вступление', () async {
    for (final s in [1, 2, 36, 55, 114]) {
      final e = await tafsir.forVerse(s, 1);
      expect(e, isNotNull, reason: 'сура $s');
      expect(e!.intro, isNotEmpty, reason: 'сура $s');
    }
  });

  test('аят без толкования отдаёт вступление к суре', () async {
    // Суры с разрозненными буквами: у «Алиф Лям Мим Сад» толкования нет.
    final e = await tafsir.forVerse(7, 1);
    expect(e, isNotNull);
    expect(e!.hasText, isFalse);
    expect(e.intro, isNotEmpty);
    expect(e.rangeLabel, isEmpty);
  });

  test('несуществующий аят не роняет поиск', () async {
    expect(await tafsir.forVerse(1, 999), isNotNull); // вернёт вступление
    expect(await tafsir.forVerse(999, 1), isNull);
  });
}
