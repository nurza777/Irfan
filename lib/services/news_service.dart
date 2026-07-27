import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Новость от устаза (публикуется из приложения «Ирфан Устаз»).
class NewsItem {
  final String title;
  final String body;
  final DateTime? date;
  const NewsItem({required this.title, required this.body, this.date});

  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
        title: (j['title'] as String?)?.trim() ?? '',
        body: (j['body'] as String?)?.trim() ?? '',
        date: DateTime.tryParse((j['date'] as String?) ?? ''),
      );
}

/// Лента новостей с сервера (тот же адрес, что и курсы, эфир — [ApiConfig]).
class NewsService {
  static Future<List<NewsItem>> fetch() async {
    try {
      final base = await ApiConfig.base();
      final r = await http
          .get(Uri.parse('$base/news.json'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return [];
      final j = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(r.bodyBytes)) as Map);
      final items = ((j['items'] as List?) ?? [])
          .map((e) => NewsItem.fromJson(Map<String, dynamic>.from(e)))
          .where((n) => n.title.isNotEmpty || n.body.isNotEmpty)
          .toList();
      // Новые сверху.
      items.sort((a, b) => (b.date ?? DateTime(2000))
          .compareTo(a.date ?? DateTime(2000)));
      return items;
    } catch (e) {
      debugPrint('news fetch error: $e');
      return [];
    }
  }
}
