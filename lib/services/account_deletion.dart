import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'auth_service.dart';
import 'device_key.dart';

/// Удаление аккаунта из самого приложения.
///
/// App Store требует, чтобы приложение, которое заводит аккаунты, давало их
/// удалить, не выходя из него (Guideline 5.1.1(v)): формы обратной связи
/// недостаточно. Удаляем в два шага — запись на сервере и все следы на
/// устройстве.
class AccountDeletion {
  const AccountDeletion._();

  /// Что стирается вместе с аккаунтом: личные данные и всё, что накоплено
  /// человеком. Настройки приложения (язык, город, шрифт Корана) не трогаем —
  /// это не данные аккаунта, а вид приложения на этом телефоне.
  static const _exactKeys = [
    'auth_users',
    'auth_current',
    'coins_spent',
    'coins_redemptions',
    'quran_bookmarks',
    'quran_notes',
    'private_zikrs',
    'zikr_goals',
  ];

  /// Ключи по префиксу: история трекера, счётчики зикров и позиции в уроках
  /// лежат по дням и по ссылкам.
  static const _prefixes = [
    'tracker_',
    'zikr_counts_',
    'private_zikr_done_',
    'lesson_at_',
  ];

  /// Удаляет текущий аккаунт. Возвращает null при успехе, иначе текст ошибки.
  ///
  /// Сначала сервер, и только потом телефон: если стереть локальные данные
  /// раньше, а сервер не ответит, удалять на нём станет нечего — аккаунта
  /// в приложении уже не будет, а запись в реестре останется навсегда.
  static Future<String?> deleteCurrent(AuthService auth) async {
    final account = auth.current;
    if (account == null) return 'Вы не вошли в аккаунт';

    try {
      final base = await ApiConfig.base();
      final secret = await DeviceKey.get();
      final r = await http
          .post(
            Uri.parse('$base/account/delete'),
            headers: {'Content-Type': 'application/json'},
            body: utf8.encode(jsonEncode({
              'phone': account.phone,
              'createdAt': account.createdAt.millisecondsSinceEpoch,
              if (secret.isNotEmpty) 'secret': secret,
            })),
          )
          .timeout(const Duration(seconds: 12));
      if (r.statusCode >= 300) {
        return 'Не удалось удалить на сервере (ответ ${r.statusCode}). '
            'Попробуйте ещё раз позже — данные пока не тронуты.';
      }
    } catch (_) {
      return 'Нет связи с сервером. Аккаунт не удалён — попробуйте, когда '
          'появится интернет.';
    }

    final prefs = await SharedPreferences.getInstance();
    for (final k in _exactKeys) {
      await prefs.remove(k);
    }
    for (final k in prefs.getKeys().toList()) {
      if (_prefixes.any(k.startsWith)) await prefs.remove(k);
    }
    return null;
  }
}
