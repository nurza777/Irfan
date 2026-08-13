import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Куда ученику писать, если нужен код подтверждения.
///
/// Автоотправка кодов не подключена: их выдаёт устаз, глядя в панель. Без
/// этого контакта указание «попросите код у устаза» — совет в пустоту:
/// человек, который меняет телефон и хочет вернуть свою историю, должен
/// уметь дотянуться до устаза в один тап.
class SupportContact {
  /// Номер WhatsApp (только цифры).
  final String whatsapp;

  /// Логин в Telegram без «@».
  final String telegram;

  /// Что показать текстом (например, часы, когда устаз отвечает).
  final String note;

  const SupportContact(
      {this.whatsapp = '', this.telegram = '', this.note = ''});

  bool get isEmpty => whatsapp.isEmpty && telegram.isEmpty;

  /// Ссылки строим САМИ из очищенных полей, а не берём готовыми с сервера:
  /// канал пока по HTTP, и произвольная ссылка из ответа уводила бы человека
  /// куда угодно.
  String? get whatsappUrl =>
      whatsapp.isEmpty ? null : 'https://wa.me/$whatsapp';
  String? get telegramUrl =>
      telegram.isEmpty ? null : 'https://t.me/$telegram';

  static String _digits(Object? v) => '$v'.replaceAll(RegExp(r'[^0-9]'), '');

  factory SupportContact.fromJson(Map<String, dynamic> j) => SupportContact(
        whatsapp: _digits(j['whatsapp'] ?? ''),
        // Логин Telegram — латиница, цифры и подчёркивание; всё прочее
        // отбрасываем, чтобы из поля нельзя было собрать чужой адрес.
        telegram: RegExp(r'[A-Za-z0-9_]{3,32}')
                .firstMatch((j['telegram'] ?? '').toString())
                ?.group(0) ??
            '',
        note: (j['note'] ?? '').toString().trim(),
      );
}

class SupportService {
  const SupportService._();

  static SupportContact? _cached;

  /// Читает контакт с сервера (один раз за запуск). Пустой контакт — значит,
  /// админ его ещё не заполнил; экраны тогда просто не показывают кнопки.
  static Future<SupportContact> get() async {
    if (_cached != null) return _cached!;
    try {
      final base = await ApiConfig.base();
      final r = await http
          .get(Uri.parse('$base/support.json'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is Map<String, dynamic>) {
          return _cached = SupportContact.fromJson(j);
        }
      }
    } catch (e) {
      debugPrint('support load error: $e');
    }
    return _cached = const SupportContact();
  }
}
