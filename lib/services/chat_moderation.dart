import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'comment_service.dart';
import 'live_service.dart';

/// Жалобы и блокировки в чате эфира.
///
/// App Store не пропускает приложения с пользовательским контентом без
/// трёх вещей (Guideline 1.2): фильтра брани (он на сервере), возможности
/// пожаловаться и возможности заблокировать автора. Блокировка — на
/// устройстве и мгновенная: ждать разбора жалобы человек не должен.
class ChatModeration {
  ChatModeration._();
  static final ChatModeration instance = ChatModeration._();

  static const _blockedKey = 'chat_blocked_authors';

  Set<String> _blocked = {};
  bool _loaded = false;

  Set<String> get blocked => Set.unmodifiable(_blocked);

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _blocked = (prefs.getStringList(_blockedKey) ?? const []).toSet();
  }

  bool isBlocked(String author) => _blocked.contains(author.trim());

  /// Скрывает сообщения этого автора. Имя — единственное, чем чат его
  /// опознаёт: своей учётной записи у комментария нет.
  Future<void> block(String author) async {
    await init();
    _blocked.add(author.trim());
    await _save();
  }

  Future<void> unblock(String author) async {
    await init();
    _blocked.remove(author.trim());
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_blockedKey, _blocked.toList());
  }

  /// Убирает из ленты сообщения заблокированных.
  List<LiveComment> filter(List<LiveComment> items) =>
      items.where((c) => !isBlocked(c.name)).toList();

  /// Отправляет жалобу администратору. true — дошла.
  Future<bool> report(LiveComment c, String reason, {String? by}) async {
    try {
      final base = await LiveService.base();
      final r = await http
          .post(
            Uri.parse('$base/comments/report'),
            headers: {'Content-Type': 'application/json'},
            body: utf8.encode(jsonEncode({
              'author': c.name,
              'text': c.text,
              'reason': reason,
              if (by != null) 'by': by,
            })),
          )
          .timeout(const Duration(seconds: 10));
      return r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
