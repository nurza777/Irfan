import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'url_safety.dart';

/// Состояние прямого эфира с сервера.
class LiveStatus {
  final bool live;
  final String title;
  final String url;
  const LiveStatus(
      {required this.live, this.title = 'Прямой эфир', this.url = ''});

  static const off = LiveStatus(live: false);
}

/// Опрос сервера трансляций.
///
/// Сервер (nginx-rtmp, см. папку `server/` в корне проекта) отдаёт
/// `status.json` вида `{"live": true, "title": "…", "url": "hls/stream.m3u8"}`.
/// Устаз запускает эфир со своего телефона (RTMP), nginx автоматически
/// переключает status.json и раздаёт HLS всем зрителям.
class LiveService {
  /// Адрес сервера трансляций — общий с курсами/новостями ([ApiConfig]).
  static Future<String> base() => ApiConfig.base();

  /// Текущий статус; любая ошибка сети трактуется как «эфира нет».
  static Future<LiveStatus> fetch() async {
    try {
      final b = await base();
      final r = await http
          .get(Uri.parse('$b/status.json'))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return LiveStatus.off;
      final j =
          Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)));
      final rawUrl = (j['url'] as String?) ?? '';
      final url = rawUrl.isEmpty
          ? ''
          : (rawUrl.startsWith('http') ? rawUrl : '$b/$rawUrl');
      // URL потока приходит с сервера — не проигрываем ничего, кроме http/https.
      final safeUrl = isSafeMediaUrl(url) ? url : '';
      return LiveStatus(
        live: j['live'] == true && safeUrl.isNotEmpty,
        title: (j['title'] as String?)?.trim().isNotEmpty == true
            ? (j['title'] as String).trim()
            : 'Прямой эфир',
        url: safeUrl,
      );
    } catch (e) {
      debugPrint('live fetch error: $e');
      return LiveStatus.off;
    }
  }
}
