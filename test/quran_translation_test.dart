import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/quran_translations.dart';
import 'package:quran/quran.dart' as quran;

/// Перевод Корана — материалы Azan.ru (с разрешения правообладателя).
///
/// Главное, что здесь проверяется, — **совпадение нумерации**. У azan.ru
/// ханафитское деление суры «аль-Фатиха»: басмала аятом не считается, а
/// последний аят разбит надвое, то есть их 1:1 — это стандартный 1:2.
/// Арабский текст приложение берёт из пакета `quran` со стандартной
/// нумерацией. Без поправки перевод встал бы не к тем аятам, и заметить это
/// можно было бы только глазами, в самой читаемой суре.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> tr;

  setUpAll(() async {
    final t = translationById('azan');
    final data = await rootBundle.load(t.asset);
    tr = Map<String, String>.from(
        jsonDecode(utf8.decode(gzip.decode(data.buffer.asUint8List())))
            as Map);
  });

  test('перевод есть у каждого аята Корана', () {
    var missing = <String>[];
    for (var s = 1; s <= 114; s++) {
      for (var a = 1; a <= quran.getVerseCount(s); a++) {
        if ((tr['$s:$a'] ?? '').trim().isEmpty) missing.add('$s:$a');
      }
    }
    expect(missing, isEmpty, reason: 'нет перевода: ${missing.take(10)}');
    expect(tr.length, 6236);
  });

  test('аль-Фатиха совпадает со стандартной нумерацией', () {
    expect(tr['1:1'], contains('именем Аллаха'));   // басмала — аят 1
    expect(tr['1:2'], contains('Вся хвала Аллаху'));
    expect(tr['1:4'], contains('Судного дня'));
    // Стандартный седьмой аят — это склеенные шестой и седьмой у azan.ru.
    expect(tr['1:7'], contains('облагодетельствовал'));
    expect(tr['1:7'], contains('заблудших'));
  });

  test('начало сур не съехало', () {
    expect(tr['2:1'], contains('Алиф'));
    expect(tr['36:1'], contains('Син'));
    expect(tr['112:1'], contains('Один'));
    expect(tr['114:6'], contains('джиннов'));
  });

  test('в тексте не осталось разметки и номеров аятов', () {
    final marked = tr.entries.where((e) =>
        e.value.contains('*') ||
        e.value.contains('<') ||
        RegExp(r'^\d').hasMatch(e.value));
    expect(marked.map((e) => '${e.key} → ${e.value}').take(5), isEmpty);
  });

  test('прежние переводы из приложения убраны', () {
    // Права на них не подтверждены, и раздавать их полными текстами в
    // каждой сборке нельзя (см. шапку quran_translations.dart).
    final ids = quranTranslations.map((t) => t.id).toSet();
    for (final gone in ['kuliev', 'porokhova', 'osmanov', 'krachkovsky', 'translit',
                        'abuadel', 'muntahab', 'sablukov', 'kazakh']) {
      expect(ids, isNot(contains(gone)));
    }
    expect(ids, contains('azan'));
    expect(ids.length, 1, reason: 'перевод должен остаться один');
    // Неизвестный id из настроек прежней сборки не должен ронять выбор.
    expect(translationById('kuliev').id, 'azan');
  });
}
