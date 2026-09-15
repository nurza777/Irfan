import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'device_key.dart';

/// Строка в таблице соревнования.
class RatingRow {
  final int rank;
  final String name;
  final int points;
  final int streak;
  final int prayers;

  /// Это я — по этой метке подсвечиваем свою строку. Телефонов сервер не
  /// присылает вовсе, опознать себя иначе нельзя.
  final bool me;

  const RatingRow({
    required this.rank,
    required this.name,
    required this.points,
    required this.streak,
    required this.prayers,
    required this.me,
  });

  factory RatingRow.fromJson(Map<String, dynamic> j) => RatingRow(
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        points: (j['points'] as num?)?.toInt() ?? 0,
        streak: (j['streak'] as num?)?.toInt() ?? 0,
        prayers: (j['prayers'] as num?)?.toInt() ?? 0,
        me: j['me'] == true,
      );
}

/// Приглашения: свой код и сколько человек пришло по нему.
///
/// Очков за приглашения сейчас не дают (см. сервер, раздел соревнования):
/// код только складывает круг друзей.
class ReferralInfo {
  final String code;
  final int invited;   // сколько всего пришло по коду

  const ReferralInfo({this.code = '', this.invited = 0});

  factory ReferralInfo.fromJson(Map<String, dynamic> j) => ReferralInfo(
        code: (j['code'] ?? '').toString(),
        invited: (j['invited'] as num?)?.toInt() ?? 0,
      );
}

/// Чем закончилась попытка получить таблицу.
///
/// Различать обязательно. Отказ сервера и обрыв связи — разные беды, и
/// человеку про них надо говорить разное. Ровно на этом уже спотыкался чат
/// поддержки: оба случая возвращали null, и отказ показывался как «нет
/// связи» — совет проверить интернет там, где интернет ни при чём.
enum RatingStatus {
  ok,

  /// Сервер не признал устройство (чужой или отсутствующий ключ).
  denied,

  /// Записи об этом ученике на сервере ещё нет: анкета не дошла.
  noProfile,

  offline,
}

class Rating {
  final List<RatingRow> top;
  final List<RatingRow> friends;
  final int? myRank;
  final int myPoints;
  final int total;
  final bool hidden;
  final ReferralInfo referral;
  final RatingStatus status;

  const Rating({
    this.status = RatingStatus.ok,
    this.top = const [],
    this.friends = const [],
    this.myRank,
    this.myPoints = 0,
    this.total = 0,
    this.hidden = false,
    this.referral = const ReferralInfo(),
  });
}

/// Соревнование: топ-100, круг друзей и приглашения.
///
/// Всё считает сервер. Клиенту нельзя: он и так сам ведёт статистику, а если
/// бы он же составлял таблицу, то любой мог бы объявить себя первым.
class RatingService {
  const RatingService._();

  static Future<Map<String, String>> _creds(String phone) async {
    final secret = await DeviceKey.get();
    return {'phone': phone, if (secret.isNotEmpty) 'secret': secret};
  }

  /// Таблица и приглашения.
  static Future<Rating> load(String phone) async {
    try {
      final base = await ApiConfig.base();
      final r = await http
          .post(Uri.parse('$base/rating'),
              headers: {'Content-Type': 'application/json; charset=utf-8'},
              body: utf8.encode(jsonEncode(await _creds(phone))))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 403) {
        return const Rating(status: RatingStatus.denied);
      }
      if (r.statusCode == 404) {
        return const Rating(status: RatingStatus.noProfile);
      }
      if (r.statusCode != 200) {
        return const Rating(status: RatingStatus.offline);
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return const Rating(status: RatingStatus.offline);
      final me = (j['me'] as Map?) ?? const {};
      List<RatingRow> rows(Object? raw) => [
            for (final e in (raw as List?) ?? const [])
              if (e is Map) RatingRow.fromJson(Map<String, dynamic>.from(e))
          ];
      return Rating(
        top: rows(j['top']),
        friends: rows(j['friends']),
        myRank: (me['rank'] as num?)?.toInt(),
        myPoints: (me['points'] as num?)?.toInt() ?? 0,
        total: (me['total'] as num?)?.toInt() ?? 0,
        hidden: me['hidden'] == true,
        referral: ReferralInfo.fromJson(
            Map<String, dynamic>.from((j['referral'] as Map?) ?? const {})),
      );
    } catch (e) {
      debugPrint('rating load: $e');
      return const Rating(status: RatingStatus.offline);
    }
  }

  /// Человеческое объяснение отказа сервера. Вынесено отдельно, чтобы
  /// проверять тестом: на экране должно быть сказано, что именно не так,
  /// а не «ошибка».
  @visibleForTesting
  static String reasonFor(String serverError) => switch (serverError) {
        'already invited' => 'Код уже введён — его вводят один раз',
        'self' => 'Это ваш собственный код',
        'mutual' => 'Вы уже пригласили этого человека',
        'unknown code' => 'Такого кода нет',
        'bad code' => 'Код состоит из шести знаков',
        _ => 'Не удалось применить код',
      };

  /// Вводит код пригласившего. Возвращает null при успехе, иначе — причину.
  static Future<String?> applyCode(String phone, String code) async {
    try {
      final base = await ApiConfig.base();
      final body = await _creds(phone)..['code'] = code.trim().toUpperCase();
      final r = await http
          .post(Uri.parse('$base/referral/apply'),
              headers: {'Content-Type': 'application/json; charset=utf-8'},
              body: utf8.encode(jsonEncode(body)))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final err = (j is Map ? j['error'] : '').toString();
      return reasonFor(err);
    } catch (e) {
      debugPrint('referral apply: $e');
      return 'Нет связи с сервером';
    }
  }
}
