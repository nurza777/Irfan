import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Секрет этого устройства — им приложение доказывает серверу, что запись
/// ученика принадлежит ему.
///
/// Пароля у ученика на сервере нет: аккаунт живёт на телефоне, а сервер
/// знает только номер. Пока секрета не было, любой, кто знает номер, мог
/// переписать чужую анкету, выкупить чужие коины или удалить аккаунт.
/// Секрет заводится один раз, лежит в Keychain и никуда больше не уходит —
/// на сервере хранится только его хеш.
class DeviceKey {
  const DeviceKey._();

  static const _key = 'irfan_device_secret';
  static const _storage = FlutterSecureStorage(
    // Keychain переживает переустановку — но локальный аккаунт нет, так что
    // после переустановки человек регистрируется заново и просто закрепляет
    // за собой новую запись.
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static String? _cached;

  /// Возвращает секрет, создавая его при первом обращении. Пустая строка —
  /// хранилище недоступно (тогда сервер работает по старым правилам).
  static Future<String> get() async {
    if (_cached != null) return _cached!;
    try {
      var v = await _storage.read(key: _key);
      if (v == null || v.length < 16) {
        v = _generate();
        await _storage.write(key: _key, value: v);
      }
      _cached = v;
      return v;
    } catch (_) {
      return '';
    }
  }

  static String _generate() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes);
  }
}
