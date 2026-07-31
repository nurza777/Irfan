import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Устаз в реестре: заводится сам из приложения «Ирфан Устаз», ученикам
/// показывается только после одобрения админом.
class Teacher {
  final String id;
  final String name;
  final String bio;
  final String status;

  const Teacher({
    required this.id,
    required this.name,
    required this.bio,
    required this.status,
  });

  bool get approved => status == 'approved';

  factory Teacher.fromJson(Map<String, dynamic> j) => Teacher(
        id: j['id'] as String? ?? '',
        name: (j['name'] as String? ?? '').trim(),
        bio: (j['bio'] as String? ?? '').trim(),
        status: j['status'] as String? ?? 'pending',
      );
}

class TeachersService {
  /// null — сервер недоступен. Пустой список — реестр пока не заполнен;
  /// это не то же самое, и экран показывает разные сообщения.
  static Future<List<Teacher>?> fetch() async {
    try {
      final base = await ApiConfig.base();
      final r = await http
          .get(Uri.parse('$base/teachers.json'))
          .timeout(const Duration(seconds: 8));
      // Реестра может ещё не быть на сервере — это не ошибка сети,
      // просто пока никто не зарегистрировался.
      if (r.statusCode == 404) return const [];
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final raw = j is Map ? j['teachers'] : j;
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Teacher.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.id.isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }
}
