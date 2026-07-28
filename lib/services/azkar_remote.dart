/// Азкары с сервера: устаз добавляет их в своём приложении, админ одобряет.
///
/// Встроенный набор ([buildAzkarCategories]) остаётся основой — он выверен и
/// работает офлайн. Серверные категории добавляются к нему, поэтому потеря
/// сети или пустой `azkar.json` ничего не ломают.
///
/// Арабский текст набирают люди (устаз), а не приложение — это и было целью
/// переноса азкаров на сервер.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'azkar_data.dart';

class AzkarRemote {
  /// Загружает серверные категории. При любой ошибке — пустой список.
  static Future<List<AzkarCategory>> fetch() async {
    try {
      final base = await ApiConfig.base();
      final r = await http
          .get(Uri.parse('$base/azkar.json'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return const [];
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return const [];
      final cats = j['categories'];
      if (cats is! List) return const [];
      return cats
          .whereType<Map>()
          .map(_category)
          .where((c) => c.items.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static AzkarCategory _category(Map c) {
    final rawItems = c['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().map(_azkar).where((a) => a.isValid).toList()
        : <Azkar>[];
    return AzkarCategory(
      title: _str(c['title'], 'Азкары устаза', 60),
      subtitle: _str(c['subtitle'], '', 80),
      icon: Icons.auto_awesome,
      items: items,
    );
  }

  static Azkar _azkar(Map a) => Azkar(
        arabic: _str(a['arabic'], '', 2000),
        translit: _str(a['translit'], '', 300),
        meaning: _str(a['meaning'], '', 600),
        count: _count(a['count']),
        source: _str(a['source'], '', 80),
      );

  static String _str(Object? v, String fallback, int max) {
    final s = (v is String ? v : '').trim();
    if (s.isEmpty) return fallback;
    return s.length > max ? s.substring(0, max) : s;
  }

  static int _count(Object? v) {
    final n = v is num ? v.toInt() : int.tryParse('$v') ?? 1;
    return n.clamp(1, 1000);
  }
}

extension on Azkar {
  /// Без арабского текста карточка бессмысленна.
  bool get isValid => arabic.isNotEmpty;
}
