import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Товар в магазине обмена коинов (1 коин = 1 сом).
class ShopItem {
  final String id;
  final String title;
  final String subtitle;
  final int cost;
  final IconData icon;
  const ShopItem(
      this.id, this.title, this.subtitle, this.cost, this.icon);
}

const shopItems = <ShopItem>[
  ShopItem('tasbih', 'Тасбих', 'Чётки для зикра — 500 сом', 500,
      Icons.blur_circular),
  ShopItem('book', 'Книга', 'Исламская книга — 700 сом', 700,
      Icons.menu_book_outlined),
  ShopItem('course', 'Скидка на курсы', 'Скидка 1000 сом на курсы', 1000,
      Icons.school_outlined),
];

/// Запись о выкупе награды.
class Redemption {
  final String itemId;
  final String title;
  final int cost;
  final String code;
  final DateTime date;
  const Redemption(
      {required this.itemId,
      required this.title,
      required this.cost,
      required this.code,
      required this.date});

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'title': title,
        'cost': cost,
        'code': code,
        'date': date.toIso8601String(),
      };

  factory Redemption.fromJson(Map<String, dynamic> j) => Redemption(
        itemId: j['itemId'] as String? ?? '',
        title: j['title'] as String? ?? '',
        cost: (j['cost'] as num?)?.toInt() ?? 0,
        code: j['code'] as String? ?? '',
        date: DateTime.tryParse(j['date'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Хранит потраченные коины и историю выкупов.
class ShopService {
  static const _spentKey = 'coins_spent';
  static const _redemptionsKey = 'coins_redemptions';

  final SharedPreferences _prefs;
  ShopService(this._prefs);

  static Future<ShopService> create() async =>
      ShopService(await SharedPreferences.getInstance());

  int get spent => _prefs.getInt(_spentKey) ?? 0;

  List<Redemption> get redemptions {
    final raw = _prefs.getString(_redemptionsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Redemption.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    } catch (_) {
      return [];
    }
  }

  /// Списывает стоимость и записывает выкуп. Проверку баланса делает вызывающий.
  Future<Redemption> redeem(ShopItem item) async {
    final code = _genCode();
    await _prefs.setInt(_spentKey, spent + item.cost);
    final list = redemptions
      ..insert(
          0,
          Redemption(
              itemId: item.id,
              title: item.title,
              cost: item.cost,
              code: code,
              date: DateTime.now()));
    await _prefs.setString(
        _redemptionsKey, jsonEncode(list.map((r) => r.toJson()).toList()));
    return list.first;
  }

  String _genCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    final s =
        List.generate(5, (_) => chars[rng.nextInt(chars.length)]).join();
    return 'IRF-$s';
  }
}
