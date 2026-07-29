import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

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

  /// Выкупает награду НА СЕРВЕРЕ: он считает баланс и выдаёт код.
  ///
  /// Раньше и списание, и код делались на устройстве — то есть коины
  /// накручивались правкой SharedPreferences, а код можно было придумать.
  /// Теперь клиент только показывает результат; локальная история нужна лишь
  /// для экрана «Мои выкупы».
  Future<RedeemResult> redeem(ShopItem item, String phone) async {
    final Map<String, dynamic> j;
    final int status;
    try {
      final base = await ApiConfig.base();
      final r = await http
          .post(
            Uri.parse('$base/redeem'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: utf8.encode(jsonEncode({
              'phone': phone,
              'itemId': item.id,
            })),
          )
          .timeout(const Duration(seconds: 8));
      status = r.statusCode;
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      j = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (e) {
      debugPrint('redeem error: $e');
      return RedeemResult.offline();
    }
    if (status == 409) {
      return RedeemResult.notEnough((j['balance'] as num?)?.toInt() ?? 0);
    }
    if (status == 403) return RedeemResult.blocked();
    if (status != 201) return RedeemResult.error();

    final entry = Redemption(
      itemId: item.id,
      title: item.title,
      cost: (j['cost'] as num?)?.toInt() ?? item.cost,
      code: j['code'] as String? ?? '',
      date: DateTime.now(),
    );
    // Локальные записи — только для истории на экране магазина.
    await _prefs.setInt(_spentKey, spent + entry.cost);
    final list = redemptions..insert(0, entry);
    await _prefs.setString(
        _redemptionsKey, jsonEncode(list.map((r) => r.toJson()).toList()));
    return RedeemResult.ok(entry);
  }
}

/// Чем закончилась попытка обмена коинов.
enum RedeemStatus { ok, notEnough, blocked, offline, error }

class RedeemResult {
  final RedeemStatus status;
  final Redemption? redemption;

  /// Баланс по данным сервера (при [RedeemStatus.notEnough] — сколько есть).
  final int? balance;

  const RedeemResult._(this.status, {this.redemption, this.balance});

  factory RedeemResult.ok(Redemption r) =>
      RedeemResult._(RedeemStatus.ok, redemption: r);
  factory RedeemResult.notEnough(int balance) =>
      RedeemResult._(RedeemStatus.notEnough, balance: balance);
  factory RedeemResult.blocked() => const RedeemResult._(RedeemStatus.blocked);
  factory RedeemResult.offline() => const RedeemResult._(RedeemStatus.offline);
  factory RedeemResult.error() => const RedeemResult._(RedeemStatus.error);

  bool get isOk => status == RedeemStatus.ok;
}
