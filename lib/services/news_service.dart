import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'response_cache.dart';

/// Фото или видео в новости.
class NewsAttachment {
  final bool isVideo;
  final String url;
  const NewsAttachment({required this.isVideo, required this.url});

  factory NewsAttachment.fromJson(Map<String, dynamic> j) => NewsAttachment(
        isVideo: (j['type'] as String?) == 'video',
        url: (j['url'] as String?)?.trim() ?? '',
      );
}

/// Новость от устаза (публикуется из приложения «Ирфан Устаз»).
class NewsItem {
  final String title;
  final String body;
  final DateTime? date;

  /// Вложения. У новостей, опубликованных до появления фото и видео, пусто.
  final List<NewsAttachment> media;

  const NewsItem({
    required this.title,
    required this.body,
    this.date,
    this.media = const [],
  });

  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
        title: (j['title'] as String?)?.trim() ?? '',
        body: (j['body'] as String?)?.trim() ?? '',
        date: DateTime.tryParse((j['date'] as String?) ?? ''),
        media: ((j['media'] as List?) ?? [])
            .map((e) =>
                NewsAttachment.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((m) => m.url.isNotEmpty)
            .toList(),
      );
}

/// Лента новостей с сервера (тот же адрес, что и курсы, эфир — [ApiConfig]).
class NewsService {
  static const cacheKey = 'news';

  /// Лента с прошлого захода — показывается сразу, пока идёт запрос.
  /// null — заходов ещё не было (пустой список значит «новостей нет»).
  static Future<List<NewsItem>?> cached() async {
    final body = await ResponseCache.read(cacheKey);
    return body == null ? null : _parse(body);
  }

  static Future<List<NewsItem>> fetch() async {
    try {
      final base = await ApiConfig.base();
      final r = await http
          .get(Uri.parse('$base/news.json'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return [];
      final body = utf8.decode(r.bodyBytes);
      final items = _parse(body);
      if (items == null) return [];
      await ResponseCache.write(cacheKey, body);
      return items;
    } catch (e) {
      debugPrint('news fetch error: $e');
      return [];
    }
  }

  static List<NewsItem>? _parse(String body) {
    try {
      final j = Map<String, dynamic>.from(jsonDecode(body) as Map);
      final items = ((j['items'] as List?) ?? [])
          .map((e) => NewsItem.fromJson(Map<String, dynamic>.from(e)))
          // Новость без текста, но с фото — полноценная: пустой остаётся
          // только запись, в которой нет вообще ничего.
          .where((n) =>
              n.title.isNotEmpty || n.body.isNotEmpty || n.media.isNotEmpty)
          .toList();
      // Новые сверху.
      items.sort((a, b) => (b.date ?? DateTime(2000))
          .compareTo(a.date ?? DateTime(2000)));
      return items;
    } catch (_) {
      return null;
    }
  }
}
