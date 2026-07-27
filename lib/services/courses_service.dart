import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'url_safety.dart';

/// Каталог: устаз → направления → курсы → уроки.
class Catalog {
  final String author;
  final List<RemoteDirection> directions;
  const Catalog({required this.author, required this.directions});
}

class RemoteDirection {
  final String title;
  final List<RemoteCourse> courses;
  const RemoteDirection({required this.title, required this.courses});

  factory RemoteDirection.fromJson(Map<String, dynamic> j) =>
      RemoteDirection(
        title: j['title'] as String? ?? '',
        courses: ((j['courses'] as List?) ?? [])
            .map((e) => RemoteCourse.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class RemoteCourse {
  final String title;
  final String subtitle;
  final List<RemoteLesson> lessons;
  const RemoteCourse(
      {required this.title, required this.subtitle, required this.lessons});

  factory RemoteCourse.fromJson(Map<String, dynamic> j) => RemoteCourse(
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String? ?? '',
        lessons: ((j['lessons'] as List?) ?? [])
            .map((e) => RemoteLesson.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class RemoteLesson {
  final String title;
  final String url;
  const RemoteLesson({required this.title, required this.url});

  factory RemoteLesson.fromJson(Map<String, dynamic> j) => RemoteLesson(
        title: j['title'] as String? ?? '',
        url: j['url'] as String? ?? '',
      );

  /// Видео, которое можно проиграть внутри приложения: прямой медиа-URL
  /// по http/https с видео-расширением. Схема проверяется, т.к. URL приходит
  /// с сервера ([isSafeMediaUrl]).
  bool get isDirectVideo {
    if (!isSafeMediaUrl(url)) return false;
    final u = url.toLowerCase().split('?').first;
    return u.endsWith('.mp4') || u.endsWith('.m3u8') || u.endsWith('.mov');
  }

  /// Можно ли открыть ссылку урока во внешнем браузере (только http/https).
  bool get isSafeLink => isSafeExternalUrl(url);
}

/// Каталог, который публикует устаз из приложения «Ирфан Устаз».
class CoursesService {
  /// null — сервер недоступен (покажем заглушку).
  static Future<Catalog?> fetch() async {
    try {
      final base = await ApiConfig.base();
      final r = await http
          .get(Uri.parse('$base/courses.json'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j =
          Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)));
      return Catalog(
        author: j['author'] as String? ?? '',
        directions: ((j['directions'] as List?) ?? [])
            .map((e) =>
                RemoteDirection.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }
}
