/// Подтверждение телефона кодом.
///
/// Сервер генерирует код, следит за сроком жизни (10 минут), числом попыток
/// и антиспамом. Приложение только запрашивает и отправляет введённый код —
/// сам код к нему не приходит, иначе подтверждение ничего бы не значило.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

enum VerifyStatus {
  ok,
  wrongCode,
  expired,
  tooSoon,
  tooManyAttempts,
  offline,
  error,
}

class VerifyResult {
  final VerifyStatus status;

  /// Сколько попыток осталось (при [VerifyStatus.wrongCode]).
  final int? attemptsLeft;

  /// Через сколько секунд можно запросить код снова ([VerifyStatus.tooSoon]).
  final int? retryAfter;

  /// Удалось ли доставить код автоматически. Пока провайдер не подключён,
  /// это всегда false — код выдаёт администратор.
  final bool delivered;

  const VerifyResult(this.status,
      {this.attemptsLeft, this.retryAfter, this.delivered = false});

  bool get isOk => status == VerifyStatus.ok;
}

class VerifyService {
  /// Просит сервер выслать код на телефон.
  static Future<VerifyResult> requestCode(String email, String phone) async {
    final r = await _post('verify/request', {'email': email, 'phone': phone});
    if (r == null) return const VerifyResult(VerifyStatus.offline);
    final (code, body) = r;
    return switch (code) {
      201 => VerifyResult(VerifyStatus.ok,
          delivered: body['delivered'] == true),
      429 => VerifyResult(VerifyStatus.tooSoon,
          retryAfter: (body['retryAfter'] as num?)?.toInt()),
      _ => const VerifyResult(VerifyStatus.error),
    };
  }

  /// Отправляет введённый пользователем код.
  static Future<VerifyResult> confirm(String email, String code) async {
    final r = await _post('verify/confirm', {'email': email, 'code': code});
    if (r == null) return const VerifyResult(VerifyStatus.offline);
    final (status, body) = r;
    return switch (status) {
      200 => const VerifyResult(VerifyStatus.ok),
      403 => VerifyResult(VerifyStatus.wrongCode,
          attemptsLeft: (body['attemptsLeft'] as num?)?.toInt()),
      410 => const VerifyResult(VerifyStatus.expired),
      429 => const VerifyResult(VerifyStatus.tooManyAttempts),
      404 => const VerifyResult(VerifyStatus.expired),
      _ => const VerifyResult(VerifyStatus.error),
    };
  }

  static Future<(int, Map<String, dynamic>)?> _post(
      String path, Map<String, dynamic> data) async {
    try {
      final base = await ApiConfig.base();
      final r = await http
          .post(
            Uri.parse('$base/$path'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: utf8.encode(jsonEncode(data)),
          )
          .timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      return (
        r.statusCode,
        decoded is Map<String, dynamic> ? decoded : <String, dynamic>{}
      );
    } catch (e) {
      debugPrint('verify error: $e');
      return null;
    }
  }
}
