import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'staff_auth.dart';

/// Направление (раздел), внутри — курсы.
class Direction {
  String title;
  List<Course> courses;
  Direction({required this.title, List<Course>? courses})
      : courses = courses ?? [];

  Map<String, dynamic> toJson() => {
        'title': title,
        'courses': courses.map((c) => c.toJson()).toList(),
      };

  factory Direction.fromJson(Map<String, dynamic> j) => Direction(
        title: j['title'] as String? ?? '',
        courses: ((j['courses'] as List?) ?? [])
            .map((e) => Course.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// Курс с уроками.
class Course {
  String title;
  String subtitle;
  List<Lesson> lessons;
  Course({required this.title, this.subtitle = '', List<Lesson>? lessons})
      : lessons = lessons ?? [];

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'lessons': lessons.map((l) => l.toJson()).toList(),
      };

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String? ?? '',
        lessons: ((j['lessons'] as List?) ?? [])
            .map((e) => Lesson.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class Lesson {
  String title;
  String url; // ссылка на видео (mp4/HLS)
  Lesson({required this.title, required this.url});

  Map<String, dynamic> toJson() => {'title': title, 'url': url};

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
        title: j['title'] as String? ?? '',
        url: j['url'] as String? ?? '',
      );
}

/// Новость/объявление для учеников.
class NewsPost {
  String title;
  String body;
  DateTime date;
  NewsPost({required this.title, required this.body, required this.date});

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'date': date.toIso8601String(),
      };

  factory NewsPost.fromJson(Map<String, dynamic> j) => NewsPost(
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Один зикр/дуа в категории азкаров.
class AzkarItem {
  final String arabic;
  final String translit;
  final String meaning;
  final int count;
  final String source;
  AzkarItem({
    required this.arabic,
    this.translit = '',
    this.meaning = '',
    this.count = 1,
    this.source = '',
  });

  Map<String, dynamic> toJson() => {
        'arabic': arabic,
        'translit': translit,
        'meaning': meaning,
        'count': count,
        'source': source,
      };

  factory AzkarItem.fromJson(Map<String, dynamic> j) => AzkarItem(
        arabic: j['arabic'] as String? ?? '',
        translit: j['translit'] as String? ?? '',
        meaning: j['meaning'] as String? ?? '',
        count: (j['count'] as num?)?.toInt() ?? 1,
        source: j['source'] as String? ?? '',
      );
}

/// Категория азкаров (вкладка у ученика).
class AzkarCategoryDto {
  final String title;
  final String subtitle;
  final List<AzkarItem> items;
  AzkarCategoryDto({
    required this.title,
    this.subtitle = '',
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory AzkarCategoryDto.fromJson(Map<String, dynamic> j) => AzkarCategoryDto(
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String? ?? '',
        items: ((j['items'] as List?) ?? [])
            .map((e) => AzkarItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// Статус заявки на модерацию.
enum ModerationStatus {
  pending('На модерации'),
  approved('Одобрено'),
  rejected('Отклонено'),
  none('Нет заявки');

  final String titleRu;
  const ModerationStatus(this.titleRu);

  static ModerationStatus parse(String? s) => switch (s) {
        'pending' => ModerationStatus.pending,
        'approved' => ModerationStatus.approved,
        'rejected' => ModerationStatus.rejected,
        _ => ModerationStatus.none,
      };
}

/// Заявка на публикацию: общая часть для курсов, новостей и азкаров.
class Submission {
  final ModerationStatus status;
  final String author;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String reason;

  const Submission({
    required this.status,
    required this.author,
    this.submittedAt,
    this.reviewedAt,
    this.reason = '',
  });

  static Submission _parse(Map<String, dynamic> j) => Submission(
        status: ModerationStatus.parse(j['status'] as String?),
        author: j['author'] as String? ?? '',
        submittedAt: DateTime.tryParse(j['submittedAt'] as String? ?? ''),
        reviewedAt: DateTime.tryParse(j['reviewedAt'] as String? ?? ''),
        reason: j['reason'] as String? ?? '',
      );
}

/// Заявка на каталог курсов.
class PendingCourses extends Submission {
  final String teacherId;
  final List<Direction> directions;

  PendingCourses({
    required super.status,
    required super.author,
    this.teacherId = '',
    super.submittedAt,
    super.reviewedAt,
    super.reason,
    required this.directions,
  });

  factory PendingCourses.fromJson(Map<String, dynamic> j) {
    final s = Submission._parse(j);
    return PendingCourses(
      status: s.status,
      author: s.author,
      teacherId: j['teacherId'] as String? ?? '',
      submittedAt: s.submittedAt,
      reviewedAt: s.reviewedAt,
      reason: s.reason,
      directions: ((j['directions'] as List?) ?? [])
          .map((e) => Direction.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// Заявка на новости.
class PendingNews extends Submission {
  final List<NewsPost> items;

  PendingNews({
    required super.status,
    required super.author,
    super.submittedAt,
    super.reviewedAt,
    super.reason,
    required this.items,
  });

  factory PendingNews.fromJson(Map<String, dynamic> j) {
    final s = Submission._parse(j);
    return PendingNews(
      status: s.status,
      author: s.author,
      submittedAt: s.submittedAt,
      reviewedAt: s.reviewedAt,
      reason: s.reason,
      items: ((j['items'] as List?) ?? [])
          .map((e) => NewsPost.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// Заявка на азкары.
class PendingAzkar extends Submission {
  final List<AzkarCategoryDto> categories;

  PendingAzkar({
    required super.status,
    required super.author,
    super.submittedAt,
    super.reviewedAt,
    super.reason,
    required this.categories,
  });

  int get itemCount => categories.fold(0, (s, c) => s + c.items.length);

  factory PendingAzkar.fromJson(Map<String, dynamic> j) {
    final s = Submission._parse(j);
    return PendingAzkar(
      status: s.status,
      author: s.author,
      submittedAt: s.submittedAt,
      reviewedAt: s.reviewedAt,
      reason: s.reason,
      categories: ((j['categories'] as List?) ?? [])
          .map((e) => AzkarCategoryDto.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// Адрес и учётка публикации эфира — сервер отдаёт их только вошедшему устазу.
class StreamConfig {
  final String rtmpUrl;
  final String streamKey;
  const StreamConfig({required this.rtmpUrl, required this.streamKey});
}

/// Всё, что кабинет устаза делает с сервером.
///
/// Публиковать ученикам напрямую отсюда нельзя: устаз отправляет заявку
/// (`*_pending`), а одобряет её админ в веб-панели. Права ограничены на
/// сервере — токен устаза не пустят ни в live-файлы, ни к данным учеников.
class StaffApi {
  const StaffApi();

  static String pendingCoursesFor(String teacherId) =>
      'courses_pending_$teacherId.json';

  Map<String, String> get _auth => StaffAuth.instance.headers;
  String? get _teacherId => StaffAuth.instance.session?.teacherId;

  Future<String> get _base => ApiConfig.base();

  // ——— Общие помощники ————————————————————————————————————————————

  Future<String?> _putJson(String path, Map<String, dynamic> data) async {
    if (_auth.isEmpty) return 'Вы не вошли в кабинет устаза';
    try {
      final base = await _base;
      final body = const JsonEncoder.withIndent('  ').convert(data);
      final r = await http
          .put(
            Uri.parse('$base/$path'),
            headers: {..._auth, 'Content-Type': 'application/json'},
            body: utf8.encode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 401) {
        // Токен отозвали или он истёк — уводим на экран входа.
        await StaffAuth.instance.refresh();
        return 'Вход больше не действует — войдите заново';
      }
      if (r.statusCode == 403) return 'Недостаточно прав';
      if (r.statusCode >= 300) return 'Сервер ответил: ${r.statusCode}';
      return null;
    } on SocketException {
      return 'Нет связи с сервером';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  Future<Map<String, dynamic>?> _getJson(String path,
      {bool authed = false}) async {
    try {
      final base = await _base;
      final r = await http
          .get(Uri.parse('$base/$path'), headers: authed ? _auth : const {})
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    }
  }

  // ——— Эфир ————————————————————————————————————————————————————

  /// Адрес и ключ публикации. Раньше ключ был константой в сборке — в
  /// публичном приложении так нельзя, поэтому его выдаёт сервер по токену.
  Future<StreamConfig?> streamConfig() async {
    final j = await _getJson('stream.json', authed: true);
    if (j == null) return null;
    final url = j['rtmpUrl'] as String? ?? '';
    final key = j['streamKey'] as String? ?? '';
    if (url.isEmpty || key.isEmpty) return null;
    return StreamConfig(rtmpUrl: url, streamKey: key);
  }

  /// Название эфира, которое увидят ученики.
  Future<String?> setLiveTitle(String title) async {
    if (_auth.isEmpty) return 'Вы не вошли в кабинет устаза';
    try {
      final base = await _base;
      final r = await http
          .put(
            Uri.parse('$base/live-title.txt'),
            headers: {..._auth, 'Content-Type': 'text/plain; charset=utf-8'},
            body: utf8.encode(title),
          )
          .timeout(const Duration(seconds: 10));
      return r.statusCode >= 300 ? 'Сервер ответил: ${r.statusCode}' : null;
    } catch (_) {
      return 'Не удалось сохранить название эфира';
    }
  }

  // ——— Курсы ————————————————————————————————————————————————————

  /// Опубликованные уроки этого устаза (для правки).
  Future<List<Direction>> fetchDirections() async {
    final live = await _getJson('courses.json');
    final tid = _teacherId;
    if (live == null || tid == null) return [];
    for (final block in (live['teachers'] as List?) ?? const []) {
      if (block is Map && block['id'] == tid) {
        return ((block['directions'] as List?) ?? [])
            .map((e) => Direction.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    }
    // Каталог прежнего вида (author + directions наверху) принадлежит одному
    // устазу — отдаём его тому, чьё имя там стоит, чтобы он продолжил править
    // свои же уроки, а не начинал с чистого листа.
    final legacyAuthor = (live['author'] as String? ?? '').trim().toLowerCase();
    final me = (StaffAuth.instance.session?.name ?? '').trim().toLowerCase();
    if (legacyAuthor.isNotEmpty && legacyAuthor == me) {
      return ((live['directions'] as List?) ?? [])
          .map((e) => Direction.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  /// Отправляет каталог на модерацию. Ученикам он попадёт после одобрения.
  Future<String?> submitDirections(List<Direction> directions, String author,
      {String bio = ''}) async {
    final tid = _teacherId;
    if (tid == null || tid.isEmpty) {
      return 'Не удалось определить устаза — войдите заново';
    }
    return _putJson(pendingCoursesFor(tid), {
      'status': 'pending',
      'submittedAt': DateTime.now().toIso8601String(),
      'author': author,
      'teacherId': tid,
      if (bio.isNotEmpty) 'bio': bio,
      'directions': directions.map((d) => d.toJson()).toList(),
    });
  }

  /// Своя заявка — чтобы показать устазу, на какой она стадии.
  Future<PendingCourses?> fetchPendingCourses() async {
    final tid = _teacherId;
    if (tid == null || tid.isEmpty) return null;
    final j = await _getJson(pendingCoursesFor(tid));
    if (j == null) return null;
    j['teacherId'] = (j['teacherId'] as String?) ?? tid;
    return PendingCourses.fromJson(j);
  }

  /// Загружает видеофайл урока. Возвращает (ссылка, null) или (null, ошибка).
  Future<(String?, String?)> uploadVideo(File file) async {
    if (_auth.isEmpty) return (null, 'Вы не вошли в кабинет устаза');
    try {
      final base = await _base;
      final safe = file.uri.pathSegments.last
          .replaceAll(RegExp(r'[^\w.\-]'), '_');
      final name = '${DateTime.now().millisecondsSinceEpoch}_$safe';
      final req = http.StreamedRequest(
          'PUT', Uri.parse('$base/uploads/$name'))
        ..headers.addAll({..._auth, 'Content-Type': 'video/mp4'})
        ..contentLength = await file.length();
      // Файл урока — сотни мегабайт. Сначала запускаем отправку, и только
      // потом подаём в неё файл через addStream: он держит обратное давление
      // и читает ровно столько, сколько уходит в сеть. Если сперва наполнять
      // sink, а отправку начинать после, весь файл окажется в памяти.
      final sending = req.send();
      await req.sink.addStream(file.openRead());
      await req.sink.close();
      final resp = await http.Response.fromStream(await sending);
      if (resp.statusCode == 401) return (null, 'Войдите в кабинет заново');
      if (resp.statusCode == 415) {
        return (null, 'Такой тип файла загружать нельзя');
      }
      if (resp.statusCode >= 300) return (null, 'Сервер: ${resp.statusCode}');
      // Сервер мог переименовать файл (транслитерация) и отдаёт итоговый адрес.
      try {
        final j = Map<String, dynamic>.from(
            jsonDecode(utf8.decode(resp.bodyBytes)));
        final url = j['publicUrl'] as String?;
        if (url != null && url.isNotEmpty) return (url, null);
      } catch (_) {}
      return ('$base/uploads/$name', null);
    } catch (e) {
      return (null, 'Ошибка загрузки: $e');
    }
  }

  // ——— Новости ————————————————————————————————————————————————————

  Future<List<NewsPost>> fetchNews() async {
    final j = await _getJson('news.json');
    if (j == null) return [];
    return ((j['items'] as List?) ?? [])
        .map((e) => NewsPost.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<String?> submitNews(List<NewsPost> items, String author) =>
      _putJson('news_pending.json', {
        'status': 'pending',
        'submittedAt': DateTime.now().toIso8601String(),
        'author': author,
        'items': items.map((n) => n.toJson()).toList(),
      });

  Future<PendingNews?> fetchPendingNews() async {
    final j = await _getJson('news_pending.json');
    return j == null ? null : PendingNews.fromJson(j);
  }

  // ——— Азкары ————————————————————————————————————————————————————

  Future<List<AzkarCategoryDto>> fetchAzkar() async {
    final j = await _getJson('azkar.json');
    if (j == null) return [];
    return ((j['categories'] as List?) ?? [])
        .map((e) => AzkarCategoryDto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<String?> submitAzkar(
          List<AzkarCategoryDto> categories, String author) =>
      _putJson('azkar_pending.json', {
        'status': 'pending',
        'submittedAt': DateTime.now().toIso8601String(),
        'author': author,
        'categories': categories.map((c) => c.toJson()).toList(),
      });

  Future<PendingAzkar?> fetchPendingAzkar() async {
    final j = await _getJson('azkar_pending.json');
    return j == null ? null : PendingAzkar.fromJson(j);
  }
}
