import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'url_safety.dart';

/// Каталог: устазы → направления → курсы → уроки.
///
/// Раньше каталог принадлежал одному устазу (`{author, directions}`). Теперь
/// устазов несколько, и каждый занимает свой блок в `teachers`. Старый вид
/// продолжаем читать — иначе после обновления сервера ученики остались бы без
/// уроков, пока устаз не опубликует каталог заново.
class Catalog {
  final List<TeacherCourses> teachers;
  const Catalog({required this.teachers});

  factory Catalog.fromJson(Map<String, dynamic> j) {
    final raw = j['teachers'];
    final out = <TeacherCourses>[
      if (raw is List)
        ...raw
            .whereType<Map>()
            .map((e) => TeacherCourses.fromJson(Map<String, dynamic>.from(e)))
            .where((t) => t.id.isNotEmpty),
    ];
    // Блок прежнего вида (author + directions на верхнем уровне) добавляем
    // РЯДОМ с новыми, а не вместо них: в переходное время в файле лежит и то
    // и другое, и его владелец не должен пропасть из списка, пока сам не
    // опубликует каталог заново.
    final dirs = (j['directions'] as List?) ?? const [];
    if (dirs.isNotEmpty) {
      out.add(TeacherCourses(
        id: legacyTeacherId,
        name: j['author'] as String? ?? '',
        bio: '',
        directions: dirs
            .whereType<Map>()
            .map((e) => RemoteDirection.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      ));
    }
    return Catalog(teachers: out);
  }

  /// Опознаватель устаза из каталога прежнего вида, у которого id не было.
  static const legacyTeacherId = 'legacy';

  TeacherCourses? byId(String id) {
    for (final t in teachers) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// Уроки одного устаза.
class TeacherCourses {
  final String id;
  final String name;
  final String bio;
  final List<RemoteDirection> directions;

  const TeacherCourses({
    required this.id,
    required this.name,
    required this.bio,
    required this.directions,
  });

  factory TeacherCourses.fromJson(Map<String, dynamic> j) => TeacherCourses(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? j['author'] as String? ?? '',
        bio: j['bio'] as String? ?? '',
        directions: ((j['directions'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => RemoteDirection.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  int get courseCount =>
      directions.fold(0, (sum, d) => sum + d.courses.length);

  int get lessonCount => directions.fold(
      0, (sum, d) => sum + d.courses.fold(0, (s, c) => s + c.lessons.length));
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
      return Catalog.fromJson(j);
    } catch (_) {
      return null;
    }
  }
}
