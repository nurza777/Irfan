import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/books_service.dart';

/// Каталог книг приходит с сервера, и приложение ему не доверяет вслепую:
/// из имён файлов на телефоне складываются пути, а негодная запись не
/// должна ронять весь список.
void main() {
  test('в список попадают только годные записи', () {
    final list = BooksService.parse('''{"items": [
      {"id": "b1", "title": "Рияд ас-Салихин", "file": "kitab.pdf"},
      {"id": "b2", "title": "", "file": "bez-nazvaniya.pdf"},
      {"id": "b3", "title": "Без файла"},
      {"id": "b4", "title": "Не PDF", "file": "urok.mp4"},
      {"id": "b1", "title": "Повтор id", "file": "drugoy.pdf"},
      "мусор"
    ]}''')!;
    expect(list.map((b) => b.id), ['b1']);
    expect(list.single.title, 'Рияд ас-Салихин');
  });

  test('битый ответ — null, а пустой каталог — пустой список', () {
    // Разница важна: null значит «сервер не ответил», и человеку говорится
    // «нет связи», а не «книг нет».
    expect(BooksService.parse('<html>502 Bad Gateway</html>'), isNull);
    expect(BooksService.parse('{"items": []}'), isEmpty);
  });

  test('полная ссылка вместо имени файла понимается', () {
    final b = BooksService.parse('''{"items": [{"id": "b1", "title": "К",
      "file": "https://api.irfan.kg/uploads/kitab.pdf?exp=1&sig=x",
      "cover": "/uploads/oblozhka.jpg"}]}''')!.single;
    expect(b.file, 'kitab.pdf');
    expect(b.cover, 'oblozhka.jpg');
  });

  test('имена с сервера не выводят за пределы папки книг', () {
    final b = BooksService.parse('''{"items": [{"id": "../../Library",
      "title": "К", "file": "../../secret.pdf"}]}''')!.single;
    final local = BooksService.localName(b);
    expect(local.contains('/'), isFalse);
    expect(local.startsWith('.'), isFalse);
    expect(BooksService.safeName('..hidden'), 'hidden');
  });

  test('заменили файл книги — на телефоне это другой файл', () {
    const a = Book(id: 'b1', title: 'К', file: 'kitab-v1.pdf');
    const b = Book(id: 'b1', title: 'К', file: 'kitab-v2.pdf');
    expect(BooksService.localName(a), isNot(BooksService.localName(b)));
  });

  test('страница ошибки вместо PDF распознаётся', () async {
    final dir = await Directory.systemTemp.createTemp('books_test');
    addTearDown(() => dir.delete(recursive: true));
    final pdf = File('${dir.path}/ok.pdf')..writeAsStringSync('%PDF-1.7\n...');
    final html = File('${dir.path}/bad.pdf')
      ..writeAsStringSync('<html>403</html>');
    final empty = File('${dir.path}/empty.pdf')..writeAsBytesSync([]);
    expect(await BooksService.looksLikePdf(pdf), isTrue);
    expect(await BooksService.looksLikePdf(html), isFalse);
    expect(await BooksService.looksLikePdf(empty), isFalse);
  });
}
