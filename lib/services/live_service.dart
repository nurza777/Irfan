import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'device_key.dart';
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

  /// Сердцебиение зрителя: отмечает, что этот телефон смотрит эфир, и тем же
  /// ответом получает число смотрящих. Отдельный запрос за счётчиком не
  /// нужен — он приезжает вместе с отметкой.
  ///
  /// Считаем по устройствам, а не по адресам: мобильные операторы прячут
  /// абонентов за общим адресом, и подсчёт по логам занижал бы число в разы.
  /// На сервер уходит тот же ключ устройства, что и при синхронизации
  /// аккаунта, и хранится там только его хеш и только в памяти.
  static Future<int?> ping() async {
    try {
      final b = await base();
      final key = await DeviceKey.get();
      if (key.isEmpty) return null;
      final r = await http
          .post(
            Uri.parse('$b/live/ping'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: utf8.encode(jsonEncode({'key': key})),
          )
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      final j =
          Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)));
      return (j['viewers'] as num?)?.toInt();
    } catch (e) {
      debugPrint('live ping error: $e');
      return null;
    }
  }

  /// Сколько сейчас смотрит — для кабинета устаза. Устаз спрашивает, а не
  /// пингует: иначе он посчитал бы сам себя зрителем собственного эфира.
  static Future<int?> viewers() async {
    try {
      final b = await base();
      final r = await http
          .get(Uri.parse('$b/live/viewers'))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      final j =
          Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)));
      return (j['viewers'] as num?)?.toInt();
    } catch (e) {
      debugPrint('live viewers error: $e');
      return null;
    }
  }
}
