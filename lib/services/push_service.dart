import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'device_key.dart';

/// Пуш-уведомления о начале эфира.
///
/// Зачем вообще: эфир начинается непредсказуемо, и напоминание к нему заранее
/// не поставишь — в отличие от намаза, время которого известно на годы вперёд.
/// Узнать «эфир идёт прямо сейчас» можно только push-ем от сервера.
///
/// Регистрируемся ТОЛЬКО когда человек сам включил уведомления об эфирах.
/// Подписка без разрешения даёт токен, по которому нечего показать, а лишний
/// системный запрос на ревью в App Store вызывает вопросы.
class PushService {
  PushService._();

  static const _channel = MethodChannel('kg.irfan.irfan/push');

  static bool _wired = false;
  static String? _token;

  /// Последний известный токен устройства — для отладки.
  static String? get token => _token;

  /// Начинает подписку на APNs и отправку токена на сервер.
  ///
  /// Идемпотентно: обработчик канала ставится один раз, повторные вызовы
  /// лишь просят систему выдать токен заново (она отдаст тот же).
  static Future<void> enable() async {
    if (!Platform.isIOS) return;   // Android — отдельная история, FCM
    debugPrint('push: включаю подписку на APNs');
    if (!_wired) {
      _channel.setMethodCallHandler(_onCall);
      _wired = true;
    }
    try {
      await _channel.invokeMethod<void>('register');
      // Токен мог прийти ещё до того, как мы подписались на канал.
      final pending = await _channel.invokeMethod<String>('pendingToken');
      if (pending != null && pending.isNotEmpty) await _send(pending);
    } on PlatformException catch (e) {
      debugPrint('push: подписка не удалась: $e');
    } on MissingPluginException {
      // Нативной части нет — например, сборка старее этой правки.
      debugPrint('push: канал kg.irfan.irfan/push недоступен');
    }
  }

  static Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'token' && call.arguments is String) {
      await _send(call.arguments as String);
    }
    return null;
  }

  /// Отдаёт токен серверу. Вместе с ним уходит ключ устройства — по нему
  /// сервер заменяет прежний токен этого же телефона, а не копит новые:
  /// после переустановки приложения APNs выдаёт другой токен, и без этого
  /// список рос бы бесконечно, а на мёртвые адреса уходили бы отправки.
  static Future<void> _send(String token) async {
    if (token.isEmpty || token == _token) return;
    _token = token;
    try {
      final base = await ApiConfig.base();
      final device = await DeviceKey.get();
      final r = await http
          .post(
            Uri.parse('$base/push/register'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: utf8.encode(jsonEncode({
              'token': token,
              if (device.isNotEmpty) 'device': device,
              'platform': 'ios',
            })),
          )
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 201) {
        debugPrint('push register: сервер ответил ${r.statusCode}');
        _token = null;   // попробуем ещё раз при следующем запуске
      }
    } catch (e) {
      debugPrint('push register error: $e');
      _token = null;
    }
  }
}
