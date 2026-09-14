import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'access_service.dart';
import 'certificate_service.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'device_key.dart';

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
    int? score,
    bool? hideInRating,
  }) async {
    try {
      final base = await ApiConfig.base();
      // Ключ устройства: им сервер отличает владельца записи от постороннего,
      // знающего номер (см. DeviceKey).
      final secret = await DeviceKey.get();
      final r = await http
          .post(
            Uri.parse('$base/users'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            // Пароль в открытом виде НЕ отправляем: уходит только
            // доказательство (PBKDF2 от пароля), и нужно оно ровно для
            // одного — чтобы человек вошёл в свой аккаунт с нового телефона
            // по номеру и паролю. См. AuthService.makeProof.
            body: utf8.encode(jsonEncode({
              'name': u.name,
              if (u.serverProof.isNotEmpty) 'pass': u.serverProof,
              // Опознаватель аккаунта — номер телефона; почты больше нет.
              'phone': u.phone,
              if (secret.isNotEmpty) 'secret': secret,
              // Пол необязателен: не указан — поле не отправляем вовсе,
              // чтобы в кабинете устаза не появлялось выдуманное значение.
              if (u.gender != null) 'gender': u.gender!.name,
              'age': u.age,
              // Дату шлём, чтобы она вернулась при переносе аккаунта на
              // новый телефон: иначе там возраст снова застыл бы числом.
              if (u.birthDate != null)
                'birthDate':
                    u.birthDate!.toIso8601String().substring(0, 10),
              if (u.city.isNotEmpty) 'city': u.city,
              // Дата создания аккаунта — база для серверной анти-накрутки
              // коинов (потолок 5 намазов в сутки с момента регистрации).
              'createdAt': u.createdAt.millisecondsSinceEpoch,
              if (prayersRead != null) 'prayersRead': prayersRead,
              if (streak != null) 'streak': streak,
              if (coins != null) 'coins': coins,
              // Очки соревнования — заработанное за всю историю, БЕЗ потолка
              // кошелька и без вычета трат. Кошелёк для рейтинга не годится:
              // он зажат тысячей, и все давние ученики стояли бы наравне,
              // а выкуп награды опускал бы человека в таблице.
              if (score != null) 'score': score,
              if (hideInRating != null) 'hideInRating': hideInRating,
            })),
          )
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 201) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      // Сервер возвращает и выданные доступы к курсам — сразу их применяем.
      AccessService.instance.update(j['access'] as List?);
      // Тем же ответом приходят дипломы и сертификаты.
      await CertificateService.instance.update(j['certificates'] as List?);
      return j['blocked'] == true;
    } catch (e) {
      debugPrint('user registry report error: $e');
      return null;
    }
  }
}
