import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'response_cache.dart';

/// Книга из каталога. Сам каталог правит админ в панели (раздел «Книги»).
class Book {
  final String id;
  final String title;
  final String author;
  final String description;

  /// Язык книги: `ru`, `ky` или пусто, если не указан.
  final String lang;

  /// Имя PDF в `uploads/` на сервере.
  final String file;

  /// Имя обложки в `uploads/`; пусто — обложки нет.
  final String cover;

  /// Размер PDF в байтах, 0 — неизвестен.
  final int size;

  const Book({
    required this.id,
    required this.title,
    required this.file,
    this.author = '',
    this.description = '',
    this.lang = '',
    this.cover = '',
    this.size = 0,
  });

  /// null — запись негодная (нет названия, файла или файл не PDF).
  static Book? fromJson(Map<String, dynamic> j) {
    final id = BooksService.safeName((j['id'] ?? '').toString());
    final title = (j['title'] ?? '').toString().trim();
    final file = BooksService.safeName(_lastSegment(j['file']));
    if (id.isEmpty || title.isEmpty || file.isEmpty) return null;
    if (!file.toLowerCase().endsWith('.pdf')) return null;
    return Book(
      id: id,
      title: title,
      file: file,
      author: (j['author'] ?? '').toString().trim(),
      description: (j['description'] ?? '').toString().trim(),
      lang: (j['lang'] ?? '').toString().trim(),
      cover: BooksService.safeName(_lastSegment(j['cover'])),
      size: (j['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// В каталоге может оказаться и имя, и полная ссылка — берём имя.
  static String _lastSegment(Object? v) =>
      (v ?? '').toString().split('?').first.split('/').last.trim();
}

/// Книги: каталог с сервера, скачивание PDF на телефон и место чтения.
///
/// Книгу читают со скачанного файла, а не потоком с сервера. PDF — десятки
/// мегабайт, и открывать его заново при каждом заходе значило бы снова
/// тянуть его из Германии по мобильной сети. Скачанная книга читается и без
/// интернета — в дороге, где её чаще всего и открывают.
class BooksService extends ChangeNotifier {
  BooksService._();
  static final instance = BooksService._();

  static const cacheKey = 'books';

  /// Сколько скачано у книг, которые качаются прямо сейчас (0…1).
  final Map<String, double> progress = {};

  /// Скачанные книги — по [Book.id].
  final Set<String> downloaded = {};

  /// Есть ли в каталоге хоть одна книга. Пока нет — пункта «Книги» в меню
  /// не показываем: раздел-заглушка «скоро появятся» хуже его отсутствия,
  /// а на проверке App Store за такие разделы отказывают (Guideline 2.1).
  /// Админ добавит первую книгу — пункт появится сам.
  bool hasBooks = false;

  void _setHasBooks(bool v) {
    if (v == hasBooks) return;
    hasBooks = v;
    notifyListeners();
  }

  /// Узнаёт, есть ли книги: сначала по сохранённому каталогу (мгновенно и
  /// без сети), потом по свежему. Зовётся при запуске приложения.
  Future<void> refreshAvailability() async {
    final saved = await cached();
    if (saved != null) _setHasBooks(saved.isNotEmpty);
    await fetch();   // сам обновит флаг, если сервер ответил
  }

  /// Каталог с прошлого захода — показывается сразу, пока идёт запрос.
  Future<List<Book>?> cached() async {
    final body = await ResponseCache.read(cacheKey);
    return body == null ? null : parse(body);
  }

  /// Свежий каталог. null — сервер недоступен (пустой список значит
  /// «книг нет», и путать эти случаи нельзя: человеку говорится разное).
  Future<List<Book>?> fetch() async {
    try {
      final base = await ApiConfig.base();
      final r = await http
          .get(Uri.parse('$base/books.json'))
          .timeout(const Duration(seconds: 8));
      // Каталог ещё ни разу не публиковали — это «книг нет», а не сбой.
      if (r.statusCode == 404) {
        _setHasBooks(false);
        return const [];
      }
      if (r.statusCode != 200) return null;
      final body = utf8.decode(r.bodyBytes);
      final items = parse(body);
      if (items == null) return null;
      _setHasBooks(items.isNotEmpty);
      await ResponseCache.write(cacheKey, body);
      await refreshDownloaded(items);
      unawaited(_dropStale(items));
      return items;
    } catch (e) {
      debugPrint('books fetch error: $e');
      return null;
    }
  }

  @visibleForTesting
  static List<Book>? parse(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map) return null;
      final seen = <String>{};
      final out = <Book>[];
      for (final e in (j['items'] as List?) ?? const []) {
        if (e is! Map) continue;
        final b = Book.fromJson(Map<String, dynamic>.from(e));
        // Повтор id означал бы, что две книги делят один файл на телефоне.
        if (b != null && seen.add(b.id)) out.add(b);
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Имя, безопасное для файловой системы и адреса: без каталогов и точек
  /// в начале. Имена приходят с сервера, и `../` в них выводил бы запись
  /// за пределы папки книг.
  @visibleForTesting
  static String safeName(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final noDots = s.replaceFirst(RegExp(r'^\.+'), '');
    return noDots.length > 120 ? noDots.substring(0, 120) : noDots;
  }

  /// Имя файла на телефоне. В нём и id, и имя PDF на сервере: админ заменил
  /// файл книги — имя сменилось, и старая копия не выдаётся за новую.
  @visibleForTesting
  static String localName(Book b) => '${b.id}__${b.file}';

  static Future<Directory> _dir() async {
    // Support, а не Documents: книги не должны вылезать в «Файлы» на iPhone
    // как документы пользователя. И не Caches: оттуда система сама удаляет
    // при нехватке места, и книга пропала бы посреди дороги без интернета.
    final root = await getApplicationSupportDirectory();
    final d = Directory('${root.path}/books');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<String> localPath(Book b) async =>
      '${(await _dir()).path}/${localName(b)}';

  Future<void> refreshDownloaded(List<Book> books) async {
    final next = <String>{};
    for (final b in books) {
      if (await File(await localPath(b)).exists()) next.add(b.id);
    }
    if (!setEquals(next, downloaded)) {
      downloaded
        ..clear()
        ..addAll(next);
      notifyListeners();
    }
  }

  /// Скачивает PDF. true — книга на телефоне.
  ///
  /// Пишем во временный файл и переименовываем только в конце: оборванная
  /// загрузка иначе оставила бы полфайла, который выглядит скачанным и не
  /// открывается.
  Future<bool> download(Book b) async {
    if (progress.containsKey(b.id)) return false;   // уже качается
    progress[b.id] = 0;
    notifyListeners();
    final path = await localPath(b);
    final part = File('$path.part');
    final client = http.Client();
    try {
      final base = await ApiConfig.base();
      final req = http.Request('GET', Uri.parse('$base/uploads/${b.file}'));
      final r = await client.send(req).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        debugPrint('book download: сервер ответил ${r.statusCode}');
        return false;
      }
      final total = r.contentLength ?? b.size;
      var got = 0;
      var lastNotified = 0.0;
      final sink = part.openWrite();
      try {
        await for (final chunk
            in r.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) {
            final p = got / total;
            // Не на каждый кусок: перерисовывать список сотни раз в секунду
            // незачем, глазу хватает шага в процент.
            if (p - lastNotified >= 0.01) {
              lastNotified = p;
              progress[b.id] = p;
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
      }
      if (!await looksLikePdf(part)) {
        // Вместо книги пришла страница ошибки (прокси, запрет) — такой
        // «PDF» не открылся бы, а числился бы скачанным.
        debugPrint('book download: получен не PDF');
        return false;
      }
      await part.rename(path);
      downloaded.add(b.id);
      return true;
    } catch (e) {
      debugPrint('book download error: $e');
      return false;
    } finally {
      client.close();
      if (await part.exists()) await part.delete();
      progress.remove(b.id);
      notifyListeners();
    }
  }

  @visibleForTesting
  static Future<bool> looksLikePdf(File f) async {
    try {
      final raf = await f.open();
      try {
        final head = await raf.read(5);
        return utf8.decode(head, allowMalformed: true) == '%PDF-';
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> delete(Book b) async {
    final f = File(await localPath(b));
    if (await f.exists()) await f.delete();
    downloaded.remove(b.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pageKey(b));
    notifyListeners();
  }

  /// Удаляет с телефона книги, которых больше нет в каталоге (или чей файл
  /// заменён): иначе они занимали бы место вечно, а удалить их из
  /// приложения было бы нельзя — в списке их уже нет.
  Future<void> _dropStale(List<Book> books) async {
    try {
      final keep = {for (final b in books) localName(b)};
      await for (final e in (await _dir()).list()) {
        final name = e.uri.pathSegments.last;
        if (e is File && !keep.contains(name)) await e.delete();
      }
    } catch (e) {
      debugPrint('books cleanup: $e');
    }
  }

  static String _pageKey(Book b) => 'book_page_${localName(b)}';

  /// Страница, на которой человек остановился (с 1).
  Future<int> lastPage(Book b) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_pageKey(b)) ?? 1;
  }

  Future<void> savePage(Book b, int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pageKey(b), page);
  }
}
