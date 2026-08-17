import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сертификат или диплом, выданный админом.
///
/// Приходит с сервера вместе с профилем (ответ `POST /users`) — тем же
/// ответом, что и доступы к курсам. Отдельного запроса нет: он означал бы
/// ещё один поход в сеть на каждом запуске.
class Certificate {
  /// Номер вида `IRF-2026-000147`. По нему организация опознаёт документ.
  final String number;

  /// Имя так, как его вписал админ при выдаче. Не берётся из анкеты: имя в
  /// профиле человек может поменять, а выданный документ меняться не должен.
  final String name;

  /// Вид бланка: diploma | certificate | gift.
  final String template;
  final String lang; // ru | ky
  /// Повод: «первого модуля по чтению Корана».
  final String title;
  final String course;
  final String teacher;

  /// Кто подарил — только у подарочного.
  final String giftFrom;
  final DateTime issuedAt;

  const Certificate({
    required this.number,
    required this.name,
    required this.template,
    required this.lang,
    required this.title,
    required this.course,
    required this.teacher,
    required this.giftFrom,
    required this.issuedAt,
  });

  factory Certificate.fromJson(Map<String, dynamic> j) => Certificate(
        number: (j['number'] as String?)?.trim() ?? '',
        name: (j['name'] as String?)?.trim() ?? '',
        template: (j['template'] as String?) ?? 'diploma',
        lang: (j['lang'] as String?) == 'ky' ? 'ky' : 'ru',
        title: (j['title'] as String?)?.trim() ?? '',
        course: (j['course'] as String?)?.trim() ?? '',
        teacher: (j['teacher'] as String?)?.trim() ?? '',
        giftFrom: (j['giftFrom'] as String?)?.trim() ?? '',
        issuedAt: DateTime.fromMillisecondsSinceEpoch(
            (j['issuedAt'] as num?)?.toInt() ?? 0),
      );

  Map<String, dynamic> toJson() => {
        'number': number,
        'name': name,
        'template': template,
        'lang': lang,
        'title': title,
        'course': course,
        'teacher': teacher,
        'giftFrom': giftFrom,
        'issuedAt': issuedAt.millisecondsSinceEpoch,
      };
}

/// Выданные ученику документы.
///
/// Список сохраняется на телефоне: диплом показывают родным и в мечети, где
/// интернета может не быть вовсе, а раздел, пустеющий без сети, выглядел бы
/// как «диплом отобрали».
class CertificateService extends ChangeNotifier {
  CertificateService._();
  static final CertificateService instance = CertificateService._();

  static const _key = 'certificates';
  static const _seenKey = 'certificates_seen';

  SharedPreferences? _prefs;
  List<Certificate> _items = [];
  Set<String> _seen = {};

  List<Certificate> get items => List.unmodifiable(_items);

  /// Сколько документов человек ещё не открывал. Пушей у нас нет, и это
  /// единственный способ сообщить о выдаче — точкой в меню при следующем
  /// запуске.
  int get unseen => _items.where((c) => !_seen.contains(c.number)).length;

  bool isNew(Certificate c) => !_seen.contains(c.number);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _seen = (_prefs!.getStringList(_seenKey) ?? const []).toSet();
    _items = _decode(_prefs!.getString(_key));
    notifyListeners();
  }

  List<Certificate> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => Certificate.fromJson(Map<String, dynamic>.from(e)))
          .where((c) => c.number.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('certificates decode error: $e');
      return [];
    }
  }

  /// Свежий список с сервера. null — ответа не было (офлайн): сохранённое
  /// оставляем на месте.
  Future<void> update(List<dynamic>? raw) async {
    if (raw == null) return;
    final fresh = raw
        .whereType<Map>()
        .map((e) => Certificate.fromJson(Map<String, dynamic>.from(e)))
        .where((c) => c.number.isNotEmpty)
        .toList()
      ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    _items = fresh;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
        _key, jsonEncode(fresh.map((c) => c.toJson()).toList()));
    notifyListeners();
  }

  Future<void> markSeen(Certificate c) async {
    if (_seen.contains(c.number)) return;
    _seen.add(c.number);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setStringList(_seenKey, _seen.toList());
    notifyListeners();
  }

  /// Со сменой аккаунта на телефоне чужие документы показываться не должны.
  Future<void> clear() async {
    _items = [];
    _seen = {};
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_key);
    await _prefs!.remove(_seenKey);
    notifyListeners();
  }
}
