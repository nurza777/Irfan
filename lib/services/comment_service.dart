import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'lang.dart';
import 'live_service.dart';

/// Комментарий зрителя под прямым эфиром (как в Instagram Live).
class LiveComment {
  final int id;
  final String name;
  final String text;
  final int ts;
  const LiveComment(
      {required this.id,
      required this.name,
      required this.text,
      required this.ts});

  factory LiveComment.fromJson(Map<String, dynamic> j) => LiveComment(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] as String?)?.trim().isNotEmpty == true
            ? (j['name'] as String).trim()
            : t('Гость'),
        text: (j['text'] as String?) ?? '',
        ts: (j['ts'] as num?)?.toInt() ?? 0,
      );
}

/// Чат эфира: студенты пишут (POST), устаз читает (GET). Сервер — тот же
/// Mac, что и статус эфира ([LiveService.base]).
class CommentService {
  /// Список комментариев; ошибка сети — пустой список.
  static Future<List<LiveComment>> fetch() async {
    try {
      final b = await LiveService.base();
      final r = await http
          .get(Uri.parse('$b/comments.json'))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return [];
      final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
      return list
          .map((e) => LiveComment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('comments fetch error: $e');
      return [];
    }
  }

  /// Отправка комментария; true — успех.
  static Future<bool> post(String name, String text) async {
    try {
      final b = await LiveService.base();
      final r = await http
          .post(
            Uri.parse('$b/comments'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: utf8.encode(jsonEncode({'name': name, 'text': text})),
          )
          .timeout(const Duration(seconds: 6));
      return r.statusCode == 201;
    } catch (e) {
      debugPrint('comment post error: $e');
      return false;
    }
  }
}
