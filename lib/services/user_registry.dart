import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';

/// Реестр аккаунтов на сервере: приложение сообщает профиль студента (БЕЗ
/// пароля), чтобы админ в приложении устаза видел, кто зарегистрировался, и
/// мог управлять доступом. Отправляется по [ApiConfig] (POST /users).
class UserRegistry {
  /// Сообщает профиль и активность на сервер (для дашборда устаза).
  /// Возвращает:
  ///  - `true`  — аккаунт заблокирован администратором;
  ///  - `false` — активен;
  ///  - `null`  — сервер недоступен (офлайн не блокируем).
  static Future<bool?> report(
    UserAccount u, {
    int? prayersRead,
    int? streak,
    int? coins,
  }) async {
    try {
      final base = await ApiConfig.base();
      final r = await http
          .post(
            Uri.parse('$base/users'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            // Пароль/хеш НЕ отправляем — только профиль и активность.
            body: utf8.encode(jsonEncode({
              'name': u.name,
              'email': u.email,
              'gender': u.gender.name,
              'age': u.age,
              // Дата создания аккаунта — база для серверной анти-накрутки
              // коинов (потолок 5 намазов в сутки с момента регистрации).
              'createdAt': u.createdAt.millisecondsSinceEpoch,
              if (prayersRead != null) 'prayersRead': prayersRead,
              if (streak != null) 'streak': streak,
              if (coins != null) 'coins': coins,
            })),
          )
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 201) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      return j['blocked'] == true;
    } catch (e) {
      debugPrint('user registry report error: $e');
      return null;
    }
  }
}
