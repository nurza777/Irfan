import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/rating_service.dart';

void main() {
  test('строка таблицы читается целиком', () {
    final r = RatingRow.fromJson({
      'rank': 3,
      'name': 'Айгерим',
      'points': 1250,
      'streak': 12,
      'prayers': 240,
      'me': true,
    });
    expect(r.rank, 3);
    expect(r.name, 'Айгерим');
    expect(r.points, 1250);
    expect(r.streak, 12);
    expect(r.prayers, 240);
    expect(r.me, isTrue);
  });

  test('неполный ответ сервера не роняет разбор', () {
    // Старый сервер или урезанный ответ: полей может не быть вовсе.
    final r = RatingRow.fromJson(const {});
    expect(r.rank, 0);
    expect(r.name, '');
    expect(r.points, 0);
    expect(r.me, isFalse);
  });

  test('чужая строка не помечается как своя', () {
    expect(RatingRow.fromJson(const {'me': false}).me, isFalse);
    // Сервер отдаёт именно булево; строку «true» за правду не принимаем —
    // иначе подсветилась бы чужая строка.
    expect(RatingRow.fromJson(const {'me': 'true'}).me, isFalse);
  });

  test('сведения о приглашениях читаются', () {
    final ref = ReferralInfo.fromJson(const {'code': 'AB3K9P', 'invited': 5});
    expect(ref.code, 'AB3K9P');
    expect(ref.invited, 5);
  });

  test('ответ прежнего сервера с бонусами разбирается без ошибок', () {
    // Сервер, ещё не обновлённый, пришлёт поля бонуса. Они просто лишние.
    final ref = ReferralInfo.fromJson(const {
      'code': 'AB3K9P', 'invited': 2, 'counted': 1, 'bonus': 100,
    });
    expect(ref.code, 'AB3K9P');
    expect(ref.invited, 2);
  });

  test('у каждого отказа своё объяснение, а не «ошибка»', () {
    // Человек должен понимать, что именно не так: вводил ли он код раньше,
    // свой ли это код или такого кода нет вовсе.
    final reasons = {
      'already invited': RatingService.reasonFor('already invited'),
      'self': RatingService.reasonFor('self'),
      'mutual': RatingService.reasonFor('mutual'),
      'unknown code': RatingService.reasonFor('unknown code'),
      'bad code': RatingService.reasonFor('bad code'),
    };
    expect(reasons.values.toSet().length, reasons.length,
        reason: 'разные причины не должны давать одинаковый текст');
    for (final text in reasons.values) {
      expect(text.length, greaterThan(10));
      expect(text.toLowerCase(), isNot(contains('ошибка')));
    }
  });

  test('незнакомая причина не оставляет человека без объяснения', () {
    final text = RatingService.reasonFor('что-то новое');
    expect(text, isNotEmpty);
  });

  test('пустая таблица — это состояние, а не поломка', () {
    const r = Rating();
    expect(r.status, RatingStatus.ok);
    expect(r.top, isEmpty);
    expect(r.friends, isEmpty);
    expect(r.myRank, isNull);
    expect(r.referral.code, '');
  });

  test('состояния «отказ», «нет анкеты» и «нет связи» различаются', () {
    // Ровно та ошибка, на которой уже спотыкался чат поддержки: отказ
    // сервера показывался как «нет связи» — совет проверить интернет там,
    // где интернет ни при чём.
    const denied = Rating(status: RatingStatus.denied);
    const noProfile = Rating(status: RatingStatus.noProfile);
    const offline = Rating(status: RatingStatus.offline);
    expect({denied.status, noProfile.status, offline.status}.length, 3);
  });
}
