import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

/// Вошедший устаз: что о нём знает сервер.
class StaffSession {
  final String login;
  final String name;
  final String teacherId;
  final String role;

  const StaffSession({
    required this.login,
    required this.name,
    required this.teacherId,
    required this.role,
  });

  Map<String, dynamic> toJson() =>
      {'login': login, 'name': name, 'teacherId': teacherId, 'role': role};

  factory StaffSession.fromJson(Map<String, dynamic> j) => StaffSession(
        login: j['login'] as String? ?? '',
        name: (j['name'] as String? ?? '').trim(),
        teacherId: j['teacherId'] as String? ?? '',
        role: j['role'] as String? ?? 'ustaz',
      );
}

/// Вход устаза в свой кабинет.
///
/// Раньше приложение устаза было отдельным и носило общий пароль публикации
/// прямо в сборке. Теперь кабинет живёт внутри приложения учеников, а оно
/// уходит в App Store — зашитый пароль вытащил бы любой скачавший. Поэтому:
/// логин и пароль заводит админ в веб-панели, приложение меняет их на токен
/// (`POST /auth/token`), токен лежит в Keychain и легко отзывается с сервера.
class StaffAuth extends ChangeNotifier {
  StaffAuth._();
  static final StaffAuth instance = StaffAuth._();

  static const _tokenKey = 'irfan_staff_token';
  static const _sessionKey = 'staff_session';

  // Keychain переживает переустановку приложения, но это ровно то поведение,
  // которого мы хотим: устаз вошёл один раз и не вводит пароль заново.
  final _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  String? _token;
  StaffSession? _session;
  bool _ready = false;

  StaffSession? get session => _session;
  bool get isStaff => _session != null && _token != null;
  bool get ready => _ready;

  /// Заголовок для запросов от имени устаза. Пустой, если не вошли.
  Map<String, String> get headers =>
      _token == null ? const {} : {'Authorization': 'Bearer $_token'};

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      _token = await _storage.read(key: _tokenKey);
    } catch (_) {
      // Keychain недоступен (первый запуск до разблокировки) — просто
      // считаем, что не вошли.
      _token = null;
    }
    if (_token == null) return;
    // Пока сервер не ответил, показываем прошлую сессию: иначе кабинет
    // «пропадал» бы при каждом запуске без сети.
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_sessionKey);
    if (cached != null) {
      try {
        _session = StaffSession.fromJson(
            Map<String, dynamic>.from(jsonDecode(cached)));
      } catch (_) {}
    }
    notifyListeners();
    if (_session == null) {
      // Токен есть, а кто мы — неизвестно. Так бывает после переустановки:
      // Keychain переживает её, а настройки приложения стираются. Здесь
      // сверку приходится дождаться, иначе устаз увидит экран входа, хотя
      // вход у него действует.
      await refresh();
      return;
    }
    // Сессия известна — сверку с сервером НЕ ждём: она может занять секунды
    // на плохой связи, а кабинет должен открыться по нажатию сразу. Если
    // сервер откажет, экран закроется сам (см. StaffHome._onAuthChanged).
    unawaited(refresh());
  }

  /// Сверяет токен с сервером. Явный отказ (401) гасит сессию — так админ
  /// закрывает вход, сменив пароль или отключив учётку. Молчание сети
  /// сессию не трогает.
  Future<void> refresh() async {
    if (_token == null) return;
    final base = await ApiConfig.base();
    try {
      final r = await http
          .post(Uri.parse('$base/auth/check'), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 401 || r.statusCode == 403) {
        await _clear();
        notifyListeners();
        return;
      }
      if (r.statusCode != 200) return;
      final j = Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)));
      await _remember(StaffSession.fromJson(j));
      notifyListeners();
    } catch (_) {
      // Нет связи — оставляем прошлую сессию.
    }
  }

  /// null — вошли, иначе текст ошибки для экрана входа.
  Future<String?> login(String login, String password) async {
    final l = login.trim().toLowerCase();
    if (l.isEmpty || password.isEmpty) return 'Введите логин и пароль';
    final base = await ApiConfig.base();
    try {
      final r = await http
          .post(
            Uri.parse('$base/auth/token'),
            headers: {'Content-Type': 'application/json'},
            body: utf8.encode(jsonEncode({'login': l, 'password': password})),
          )
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 401) return 'Неверный логин или пароль';
      if (r.statusCode == 429) {
        return 'Слишком много попыток — подождите минуту';
      }
      if (r.statusCode != 200) return 'Сервер ответил: ${r.statusCode}';
      final j = Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)));
      final token = j['token'] as String?;
      if (token == null || token.isEmpty) return 'Сервер не выдал токен';
      _token = token;
      await _storage.write(key: _tokenKey, value: token);
      await _remember(StaffSession.fromJson(j));
      notifyListeners();
      return null;
    } on SocketException {
      return 'Нет связи с сервером';
    } catch (e) {
      return 'Не удалось войти: $e';
    }
  }

  Future<void> logout() async {
    final base = await ApiConfig.base();
    final head = headers;
    await _clear();
    notifyListeners();
    if (head.isEmpty) return;
    // Гасим токен и на сервере — иначе он жил бы до конца срока.
    try {
      await http
          .post(Uri.parse('$base/auth/logout'), headers: head)
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> _remember(StaffSession s) async {
    _session = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(s.toJson()));
  }

  Future<void> _clear() async {
    _token = null;
    _session = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}
