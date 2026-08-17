import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:irfan/services/certificate_service.dart';

/// Диплом показывают родным и в мечети, где сети может не быть вовсе.
/// Поэтому список живёт на телефоне, а пустой ответ сервера не должен
/// выглядеть как «документ отобрали».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> cert(String number, {int at = 1000}) => {
        'number': number,
        'name': 'Ашырматова Жаркын',
        'template': 'diploma',
        'lang': 'ru',
        'title': 'первого модуля по чтению Корана',
        'course': 'Таджвид',
        'teacher': 'Фархат ажы Юсупов Ирфан',
        'giftFrom': '',
        'issuedAt': at,
      };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CertificateService.instance.clear();
  });

  test('пришедшее с сервера сохраняется и переживает перезапуск', () async {
    await CertificateService.instance.update([cert('IRF-2026-000001')]);
    expect(CertificateService.instance.items.single.number,
        'IRF-2026-000001');

    // Перезапуск: сервис поднимается из настроек, сети ещё нет.
    await CertificateService.instance.clear();
    SharedPreferences.setMockInitialValues({
      'flutter.certificates': jsonEncode([cert('IRF-2026-000001')]),
    });
    await CertificateService.instance.init();
    expect(CertificateService.instance.items.length, 1);
    expect(CertificateService.instance.items.single.title,
        'первого модуля по чтению Корана');
  });

  test('офлайн (ответа не было) сохранённое остаётся на месте', () async {
    await CertificateService.instance.update([cert('IRF-2026-000001')]);
    await CertificateService.instance.update(null);
    expect(CertificateService.instance.items.length, 1);
  });

  test('отозванный сервером исчезает', () async {
    await CertificateService.instance.update(
        [cert('IRF-2026-000001'), cert('IRF-2026-000002')]);
    // Сервер отдаёт только действующие — отозванного в ответе просто нет.
    await CertificateService.instance.update([cert('IRF-2026-000001')]);
    expect(CertificateService.instance.items.map((c) => c.number),
        ['IRF-2026-000001']);
  });

  test('новые сверху', () async {
    await CertificateService.instance.update([
      cert('IRF-2026-000001', at: 1000),
      cert('IRF-2026-000009', at: 9000),
    ]);
    expect(CertificateService.instance.items.first.number, 'IRF-2026-000009');
  });

  test('непрочитанные считаются и гаснут при открытии', () async {
    await CertificateService.instance.update(
        [cert('IRF-2026-000001'), cert('IRF-2026-000002')]);
    expect(CertificateService.instance.unseen, 2);

    await CertificateService.instance
        .markSeen(CertificateService.instance.items.first);
    expect(CertificateService.instance.unseen, 1);
  });

  test('со сменой аккаунта чужие документы не остаются', () async {
    await CertificateService.instance.update([cert('IRF-2026-000001')]);
    await CertificateService.instance.clear();
    expect(CertificateService.instance.items, isEmpty);
    expect(CertificateService.instance.unseen, 0);
  });

  test('мусор в сохранённом не роняет раздел', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.certificates': 'не json',
    });
    await CertificateService.instance.init();
    expect(CertificateService.instance.items, isEmpty);
  });

  test('запись без номера отбрасывается: по номеру опознают документ',
      () async {
    await CertificateService.instance.update([
      cert('IRF-2026-000001'),
      {'name': 'Без номера', 'template': 'diploma'},
    ]);
    expect(CertificateService.instance.items.length, 1);
  });
}
