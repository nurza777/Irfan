import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';
import 'device_key.dart';
import 'staff_auth.dart';

/// Временная ссылка на видеоурок.
///
/// Файлы в `uploads/` раздавались всем, кто знает имя: ссылку достаточно
/// было один раз переслать, и урок смотрел кто угодно — выдача доступа к
/// курсу оставалась витриной. Теперь приложение просит ссылку у сервера, а
/// тот подписывает её на несколько часов.
///
/// Адрес урока в каталоге НЕ меняется: подпись живёт только на время
/// проигрывания. Иначе поехали бы и опубликованные ссылки, и позиции
/// просмотра, которые запоминаются по адресу урока.
class MediaLink {
  const MediaLink._();

  /// Подписанный адрес для проигрывания. При любой неудаче возвращает
  /// исходный: пока проверка на сервере не включена, он рабочий, а когда
  /// включат — сервер сам ответит отказом, и это будет честнее, чем
  /// молча не открыть урок.
  static Future<String> playable(String url, AuthService? auth) async {
    final base = await ApiConfig.base();
    if (!url.startsWith('$base/uploads/')) return url; // чужая ссылка
    try {
      final body = <String, dynamic>{
        'name': Uri.parse(url).pathSegments.last,
      };
      final headers = <String, String>{'Content-Type': 'application/json'};
      // Устаз ходит по своему токену, ученик — по ключу устройства.
      final staff = StaffAuth.instance.headers;
      if (staff.isNotEmpty) {
        headers.addAll(staff);
      } else {
        final u = auth?.current;
        final secret = await DeviceKey.get();
        if (u == null || secret.isEmpty) return url;
        body['phone'] = u.phone;
        body['createdAt'] = u.createdAt.millisecondsSinceEpoch;
        body['secret'] = secret;
      }
      final r = await http
          .post(Uri.parse('$base/media/link'),
              headers: headers, body: utf8.encode(jsonEncode(body)))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return url;
      final j = Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)));
      final signed = j['url'] as String?;
      return (signed != null && signed.isNotEmpty) ? signed : url;
    } catch (e) {
      debugPrint('media link error: $e');
      return url;
    }
  }
}
