import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Отправка сбоев на свой сервер.
///
/// Раньше падение у человека на телефоне не видел никто: он просто закрывал
/// приложение. Сторонние сервисы (Crashlytics, Sentry) требуют отдельного
/// аккаунта и SDK — для этого проекта достаточно своего сервера, который уже
/// есть.
///
/// Личных данных не отправляется: только текст ошибки, стек, версия и
/// система. Ни номера, ни имени, ни того, что человек делал.
class CrashReporter {
  const CrashReporter._();

  /// Версию приложения задаём при сборке:
  /// `flutter build ipa --dart-define=APP_VERSION=1.0.0+1`.
  /// Без этого поле останется пустым — на группировку сбоев это не влияет.
  static const _version = String.fromEnvironment('APP_VERSION');

  /// Один вид ошибки шлём один раз за запуск: если что-то падает в цикле
  /// перерисовки, иначе уйдут тысячи одинаковых запросов подряд.
  static final Set<String> _sentThisRun = {};
  static const _maxPerRun = 20;

  /// Ставит обработчики. Вызывать в main до runApp.
  static void install() {
    final flutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterOnError?.call(details);   // не глушим обычный вывод в консоль
      _send(details.exception, details.stack, fatal: false);
    };
    // Ошибки вне дерева виджетов (таймеры, обработчики потоков).
    PlatformDispatcher.instance.onError = (error, stack) {
      _send(error, stack, fatal: true);
      return false;                     // пусть Flutter обработает как обычно
    };
  }

  static void _send(Object error, StackTrace? stack, {required bool fatal}) {
    // В отладочной сборке не шлём: иначе список забьётся сбоями,
    // которые разработчик и так видит в консоли.
    if (kDebugMode) return;
    final text = error.toString();
    final trace = (stack ?? StackTrace.current).toString();
    final head = trace.split('\n').first;
    final key = '$text|$head';
    if (_sentThisRun.contains(key) || _sentThisRun.length >= _maxPerRun) return;
    _sentThisRun.add(key);
    unawaited(_post(text, trace, fatal));
  }

  static Future<void> _post(String error, String stack, bool fatal) async {
    try {
      final base = await ApiConfig.base();
      await http
          .post(
            Uri.parse('$base/crash'),
            headers: {'Content-Type': 'application/json'},
            body: utf8.encode(jsonEncode({
              'error': error,
              // Длинный стек обрезаем: верх и так самый полезный.
              'stack': stack.length > 4000 ? stack.substring(0, 4000) : stack,
              'fatal': fatal,
              if (_version.isNotEmpty) 'version': _version,
              'platform': '${Platform.operatingSystem} '
                  '${Platform.operatingSystemVersion}',
            })),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Сбой при отправке сбоя гасим молча — иначе получится петля.
    }
  }
}
