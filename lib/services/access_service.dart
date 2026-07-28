/// Доступ студента к направлениям и курсам.
///
/// Список приходит с сервера вместе с профилем (ответ `POST /users`) и живёт
/// в памяти на время сессии. Доступ, выданный на срок, сервер отдаёт только
/// пока он действует — просроченные записи до приложения не доходят.
///
/// Это витрина, а не защита: ссылки на видео по-прежнему открыты тому, кто их
/// знает. Настоящее ограничение — раздача уроков через сервер по токену,
/// отдельная задача (вместе с HTTPS).
library;

import 'package:flutter/foundation.dart';

class AccessGrant {
  final String scope; // direction | course
  final String key; // «Фикх» или «Фикх/Основы намаза»
  final DateTime? until; // null — бессрочно
  const AccessGrant({required this.scope, required this.key, this.until});

  factory AccessGrant.fromJson(Map<String, dynamic> j) => AccessGrant(
        scope: j['scope'] as String? ?? 'course',
        key: j['key'] as String? ?? '',
        until: j['until'] is num
            ? DateTime.fromMillisecondsSinceEpoch((j['until'] as num).toInt())
            : null,
      );

  bool get active => until == null || until!.isAfter(DateTime.now());
}

class AccessService extends ChangeNotifier {
  AccessService._();
  static final AccessService instance = AccessService._();

  List<AccessGrant> _grants = [];

  /// Успел ли сервер ответить. Пока нет — курсы не прячем, чтобы офлайн и
  /// медленная сеть не выглядели как «доступ отобрали».
  bool _loaded = false;

  bool get loaded => _loaded;
  List<AccessGrant> get grants => List.unmodifiable(_grants);

  void update(List<dynamic>? raw) {
    if (raw == null) return;
    _grants = raw
        .whereType<Map>()
        .map((e) => AccessGrant.fromJson(Map<String, dynamic>.from(e)))
        .where((g) => g.key.isNotEmpty && g.active)
        .toList();
    _loaded = true;
    notifyListeners();
  }

  /// Открыт ли курс: либо выдан он сам, либо всё направление целиком.
  bool canOpenCourse(String direction, String course) {
    if (!_loaded) return true; // ещё не знаем — не мешаем
    return _grants.any((g) =>
        (g.scope == 'direction' && g.key == direction) ||
        (g.scope == 'course' && g.key == '$direction/$course'));
  }

  /// Открыто ли хоть что-то внутри направления.
  bool canOpenDirection(String direction) {
    if (!_loaded) return true;
    return _grants.any((g) =>
        (g.scope == 'direction' && g.key == direction) ||
        (g.scope == 'course' && g.key.startsWith('$direction/')));
  }

  /// До какого числа открыт курс (null — бессрочно или доступа нет).
  DateTime? courseUntil(String direction, String course) {
    for (final g in _grants) {
      if (g.scope == 'course' && g.key == '$direction/$course') return g.until;
      if (g.scope == 'direction' && g.key == direction) return g.until;
    }
    return null;
  }

  void clear() {
    _grants = [];
    _loaded = false;
    notifyListeners();
  }
}
