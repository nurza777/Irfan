import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Один телефон поддержки: кому звонят и по какому номеру.
class SupportPhone {
  final String name;
  final String phone;
  const SupportPhone({required this.name, required this.phone});

  /// Ссылку для звонка собираем сами из очищенного номера — по той же
  /// причине, что и адреса мессенджеров ниже.
  String get telUrl => 'tel:$phone';
}

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

  /// Телефоны, по которым можно позвонить. Список, а не одно поле: за
  /// разные вопросы отвечают разные люди, и «позвоните в организацию»
  /// без имени вынуждает объяснять всё заново каждому, кто снял трубку.
  final List<SupportPhone> phones;

  const SupportContact(
      {this.whatsapp = '',
      this.telegram = '',
      this.note = '',
      this.phones = const []});

  bool get isEmpty => whatsapp.isEmpty && telegram.isEmpty && phones.isEmpty;

  /// Ссылки строим САМИ из очищенных полей, а не берём готовыми с сервера:
  /// канал пока по HTTP, и произвольная ссылка из ответа уводила бы человека
  /// куда угодно.
  String? get whatsappUrl =>
      whatsapp.isEmpty ? null : 'https://wa.me/$whatsapp';
  String? get telegramUrl =>
      telegram.isEmpty ? null : 'https://t.me/$telegram';

  static String _digits(Object? v) => '$v'.replaceAll(RegExp(r'[^0-9]'), '');

  /// Номер для звонка: только цифры и ведущий плюс. Всё остальное —
  /// пробелы, скобки, тире и что угодно ещё — отбрасываем: в ссылку `tel:`
  /// произвольный текст пускать нельзя.
  static String _tel(Object? v) {
    final raw = '\$v'.trim();
    final d = _digits(raw);
    if (d.length < 6 || d.length > 15) return '';   // не похоже на номер
    return raw.startsWith('+') ? '+\$d' : d;
  }

  /// Сколько телефонов показываем. Ограничение не от жадности: список
  /// приходит с сервера, и без потолка ошибка в панели превратила бы
  /// настройки в бесконечную простыню.
  static const _maxPhones = 8;

  static List<SupportPhone> _phones(Object? v) {
    if (v is! List) return const [];
    final out = <SupportPhone>[];
    for (final e in v) {
      if (e is! Map) continue;
      final phone = _tel(e['phone']);
      if (phone.isEmpty) continue;
      final name = (e['name'] ?? '').toString().trim();
      out.add(SupportPhone(
          name: name.length > 60 ? name.substring(0, 60) : name,
          phone: phone));
      if (out.length == _maxPhones) break;
    }
    return out;
  }

  factory SupportContact.fromJson(Map<String, dynamic> j) => SupportContact(
        whatsapp: _digits(j['whatsapp'] ?? ''),
        // Логин Telegram — латиница, цифры и подчёркивание; всё прочее
        // отбрасываем, чтобы из поля нельзя было собрать чужой адрес.
        telegram: RegExp(r'[A-Za-z0-9_]{3,32}')
                .firstMatch((j['telegram'] ?? '').toString())
                ?.group(0) ??
            '',
        note: (j['note'] ?? '').toString().trim(),
        phones: _phones(j['phones']),
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
