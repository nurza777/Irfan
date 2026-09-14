import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'device_key.dart';

/// Одно сообщение переписки с поддержкой.
class SupportMessage {
  final int id;

  /// `true` — написал сам ученик, `false` — ответила поддержка.
  final bool mine;
  final String text;
  final DateTime at;

  const SupportMessage(
      {required this.id,
      required this.mine,
      required this.text,
      required this.at});

  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
        id: (j['id'] as num?)?.toInt() ?? 0,
        mine: j['from'] == 'user',
        text: (j['text'] ?? '').toString(),
        at: DateTime.fromMillisecondsSinceEpoch(
            (j['ts'] as num?)?.toInt() ?? 0),
      );
}

/// Чем закончилась попытка получить переписку.
///
/// Различать обязательно: «сервер отказал» и «нет связи» — разные беды, и
/// человеку про них надо говорить разное. Раньше оба случая возвращали null,
/// и отказ показывался как «нет связи с сервером» — совет проверить интернет
/// там, где интернет ни при чём.
enum SupportChatStatus { ok, denied, offline }

class SupportChatResult {
  final SupportChatStatus status;
  final List<SupportMessage> messages;
  const SupportChatResult(this.status, [this.messages = const []]);
}

/// Переписка ученика с поддержкой.
///
/// Отличается от чата эфира двумя вещами. Во-первых, она личная: у каждого
/// своя ветка, и видят её только он и персонал. Во-вторых, она не исчезает
/// вместе с трансляцией — вопрос можно задать когда угодно и вернуться
/// за ответом.
///
/// Опознаётся человек ключом устройства, а не номером: по одному номеру
/// чужую переписку читал бы любой, кто его знает. Ключ живёт в Keychain
/// и на сервер уходит только его хеш.
class SupportChatService {
  const SupportChatService._();

  /// Сколько ответов поддержки человек ещё не видел.
  ///
  /// Пушей без ключа APNs нет, и без счётчика ответ оставался незамеченным,
  /// пока человек сам не догадается заглянуть в переписку. Счётчик виден
  /// в меню и в разделе «Поддержка».
  static final unreadCount = ValueNotifier<int>(0);

  /// Спрашивает у сервера счётчик. Ничего не отмечает прочитанным.
  static Future<void> refreshUnread(String? phone) async {
    if (phone == null || phone.isEmpty) {
      unreadCount.value = 0;
      return;
    }
    try {
      final base = await ApiConfig.base();
      final r = await http
          .post(Uri.parse('$base/support/unread'),
              headers: {'Content-Type': 'application/json; charset=utf-8'},
              body: utf8.encode(jsonEncode(await _creds(phone))))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map) unreadCount.value = (j['unread'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('support chat unread: $e');
    }
  }

  static Future<Map<String, String>> _creds(String phone) async {
    final secret = await DeviceKey.get();
    return {'phone': phone, if (secret.isNotEmpty) 'secret': secret};
  }

  /// Вся переписка.
  static Future<SupportChatResult> history(String phone) async {
    try {
      final base = await ApiConfig.base();
      final r = await http
          .post(Uri.parse('$base/support/history'),
              headers: {'Content-Type': 'application/json; charset=utf-8'},
              body: utf8.encode(jsonEncode(await _creds(phone))))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 403) {
        return const SupportChatResult(SupportChatStatus.denied);
      }
      if (r.statusCode != 200) {
        return const SupportChatResult(SupportChatStatus.offline);
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final raw = (j is Map ? j['messages'] : null) as List?;
      // Сервер отметил переписку прочитанной этим же запросом.
      unreadCount.value = 0;
      return SupportChatResult(SupportChatStatus.ok, [
        for (final m in raw ?? const [])
          if (m is Map) SupportMessage.fromJson(Map<String, dynamic>.from(m))
      ]);
    } catch (e) {
      debugPrint('support chat history: $e');
      return const SupportChatResult(SupportChatStatus.offline);
    }
  }

  /// Отправляет сообщение. Возвращает его же — или null при неудаче.
  static Future<SupportMessage?> send(String phone, String text,
      {String name = ''}) async {
    if (text.trim().isEmpty) return null;
    try {
      final base = await ApiConfig.base();
      final body = await _creds(phone)
        ..['text'] = text.trim()
        ..['name'] = name;
      final r = await http
          .post(Uri.parse('$base/support/send'),
              headers: {'Content-Type': 'application/json; charset=utf-8'},
              body: utf8.encode(jsonEncode(body)))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 201) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return null;
      return SupportMessage.fromJson(Map<String, dynamic>.from(j));
    } catch (e) {
      debugPrint('support chat send: $e');
      return null;
    }
  }
}
