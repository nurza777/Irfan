import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/certificate_service.dart';
import '../services/date_fmt.dart';

/// Бланк документа: рисуется приложением, а не приходит картинкой.
///
/// Размер задан жёстко (альбомный лист в пропорции A4) и не зависит от
/// экрана: тот же виджет уходит в файл при «Поделиться», и там ширина
/// телефона роли не играет. Показывать — через `FittedBox`.
///
/// **Про оформление.** Сейчас фон, рамка и орнамент рисуются кодом по мотивам
/// присланных образцов. Когда появятся настоящие подложки из Canva (тот же
/// бланк, но без текста), достаточно положить их в `assets/certificates/` и
/// подставить `Image.asset` вместо `_Ornament` — расположение текста
/// останется прежним.
class CertificateSheet extends StatelessWidget {
  final Certificate cert;

  /// Обращение зависит от пола, а пол сервер ученику не возвращает — он и так
  /// знает его из своей анкеты.
  final bool female;

  static const width = 1400.0;
  static const height = 990.0;

  const CertificateSheet({
    super.key,
    required this.cert,
    required this.female,
  });

  bool get _gift => cert.template == 'gift';
  bool get _ky => cert.lang == 'ky';

  String get _heading {
    if (_gift) return _ky ? 'Белек сертификаты' : 'Подарочный сертификат';
    if (cert.template == 'certificate') {
      return _ky ? 'Сертификат' : 'Сертификат';
    }
    return _ky ? 'Диплом' : 'Диплом';
  }

  String get _salute {
    if (_ky) return 'УРМАТТУУ';
    return female ? 'УВАЖАЕМАЯ' : 'УВАЖАЕМЫЙ';
  }

  /// Текст бланка. Повод («первого модуля по чтению Корана») хранится на
  /// сервере коротким, а обрамляющие слова у каждого вида свои — они взяты
  /// из присланных образцов.
  String get _body {
    final t = cert.title;
    final teacher = cert.teacher;
    if (_gift) {
      return _ky
          ? 'Бул сертификат — билимге жана руханий өнүгүүгө жасалган баалуу '
              'салым. Ал Сизге Куран курстарыбыздан өтүп, бул дүйнөдө да, '
              'акыретте да пайда алып келген баалуу билим алууга мүмкүнчүлүк '
              'берет. Алла Таала бул билимге береке берсин, аны пайдалуу жана '
              'нурлуу кылсын.'
          : 'Этот сертификат — ценный вклад в знания и духовное развитие. Он '
              'предоставляет возможность пройти наши курсы Корана и получить '
              'полезные знания, которые приносят пользу в этом мире и в '
              'вечности. Пусть Аллах дарует барракат этому знанию и сделает '
              'его источником пользы и света.';
    }
    if (cert.template == 'certificate') {
      return _ky
          ? '$t ийгиликтүү аяктаганыңыз үчүн'
              '${teacher.isEmpty ? '' : ' жана $teacher жетекчилиги астында '
                  'көрсөткөн активдүү катышууңуз менен мыкты жыйынтыктарга '
                  'жетишкениңиз үчүн'} терең ыраазычылык билдиребиз!\n\n'
              'Сизге чың ден соолук, бакубат жашоо жана мындан аркы '
              'турмушуңузда чоң ийгилик каалайбыз.'
          : 'Выражаем Вам глубокую благодарность за успешное завершение $t, а '
              'также за активное участие и достижение отличных результатов'
              '${teacher.isEmpty ? '' : ' под руководством $teacher'}!\n\n'
              'Желаем Вам крепкого здоровья, благополучной жизни и больших '
              'успехов в Вашей дальнейшей деятельности.';
    }
    return _ky
        ? '$t ийгиликтүү аяктаганыңыз, окуу процессине активдүү '
            'катышканыңыз жана жакшы натыйжаларга жетишкениңиз үчүн терең '
            'ыраазычылык билдиребиз.\n\n'
            'Сизге чың ден соолук, бакубаттык жана Куранды үйрөнүү жолунда '
            'мындан аркы ийгиликтерди каалайбыз.'
        : 'Выражаем Вам глубокую благодарность за успешное завершение $t, '
            'активное участие в учебном процессе и достигнутые хорошие '
            'результаты.\n\nЖелаем Вам крепкого здоровья, благополучия и '
            'дальнейших успехов на пути изучения Корана.';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DefaultTextStyle(
        style: const TextStyle(
            fontFamily: 'serif', color: _CertColors.ink, height: 1.5),
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.white)),
            Positioned.fill(
              child: CustomPaint(painter: _Ornament(gift: _gift)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(_gift ? 130 : 470, 56, 110, 62),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Арка с полумесяцем — над заголовком, как на образцах.
                  // Раньше она рисовалась фоном по всему листу и налезала на
                  // слово «Диплом».
                  SizedBox(
                    height: 122,
                    child: CustomPaint(painter: _Arch()),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _heading,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 68,
                      fontWeight: FontWeight.w700,
                      color: _CertColors.gold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _salute,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      letterSpacing: 8,
                      color: _CertColors.faded,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Text(
                    cert.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                        fontSize: 46, fontWeight: FontWeight.w500, height: 1.2),
                  ),
                  const SizedBox(height: 10),
                  Container(height: 1.4, color: _CertColors.rule),
                  const SizedBox(height: 26),
                  Expanded(
                    child: Text(
                      _body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 23, height: 1.62),
                    ),
                  ),
                  if (cert.giftFrom.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _ky ? '${cert.giftFrom}дан' : 'От ${cert.giftFrom}',
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  _Signature(
                    teacher: cert.teacher,
                    ky: _ky,
                  ),
                  // У подарочного по краю листа идёт золотая рамка, а логотип
                  // стоит в левом нижнем углу колонки: номер в углу листа
                  // ложился то на рамку, то на логотип. Здесь он никому не
                  // мешает.
                  if (_gift)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        '№ ${cert.number} · ${fmtDateLong(cert.issuedAt)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 17, color: _CertColors.faded, height: 1),
                      ),
                    ),
                ],
              ),
            ),
            // Номер — то, по чему организация опознаёт документ. Мелко и в
            // углу, как на бумажных бланках.
            if (!_gift)
              Positioned(
                left: 40,
                bottom: 26,
                child: Text(
                  '№ ${cert.number} · ${fmtDateLong(cert.issuedAt)}',
                  style: const TextStyle(
                      fontSize: 17, color: _CertColors.faded, height: 1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CertColors {
  static const gold = Color(0xFFC9A227);
  static const goldSoft = Color(0xFFE8D9A0);
  static const paper = Color(0xFFFBF3DC);
  static const ink = Color(0xFF1A1A1A);
  static const faded = Color(0xFF8A8A8A);
  static const rule = Color(0xFF2A2A2A);
}

/// Подпись и печать. Изображения печати у приложения нет и быть не должно:
/// это оттиск организации, его кладут отдельным файлом. Пока — та же разметка,
/// что на образцах: «МП», линия подписи и расшифровка.
class _Signature extends StatelessWidget {
  final String teacher;
  final bool ky;
  const _Signature({required this.teacher, required this.ky});

  @override
  Widget build(BuildContext context) {
    if (teacher.isEmpty) return const SizedBox(height: 40);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Image.asset('assets/images/logo.png',
                height: 70, errorBuilder: (_, _, _) => const SizedBox(width: 70)),
            Column(
              children: [
                SizedBox(
                  width: 330,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(ky ? 'МО' : 'МП',
                          style: const TextStyle(fontSize: 20)),
                      Text(ky ? 'Колу' : 'подпись',
                          style: const TextStyle(fontSize: 20)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(teacher, style: const TextStyle(fontSize: 22)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Фон: мягкое песочное пятно и силуэт мечети слева — как на образцах, — а у
/// подарочного вместо них золотая рамка.
class _Ornament extends CustomPainter {
  final bool gift;
  _Ornament({required this.gift});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    if (gift) {
      _frame(canvas, size, p);
      return;
    }
    // Песочное пятно слева-внизу.
    p.color = _CertColors.paper;
    final blob = Path()
      ..moveTo(0, size.height * 0.44)
      ..quadraticBezierTo(size.width * 0.16, size.height * 0.34,
          size.width * 0.34, size.height * 0.46)
      ..quadraticBezierTo(size.width * 0.46, size.height * 0.56,
          size.width * 0.42, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(blob, p);

    _mosque(canvas, size, p);
  }

  /// Силуэт мечети с минаретами и пальмами — светлым золотом, как подложка.
  void _mosque(Canvas canvas, Size size, Paint p) {
    p.color = _CertColors.goldSoft;
    final baseY = size.height * 0.50;
    final left = size.width * 0.04;

    void tower(double x, double w, double h) {
      canvas.drawRect(Rect.fromLTWH(x, baseY - h, w, h), p);
      canvas.drawCircle(Offset(x + w / 2, baseY - h), w * 0.75, p);
    }

    // Купол и корпус.
    final bodyRect = Rect.fromLTWH(left + 40, baseY - 90, 200, 90);
    canvas.drawRect(bodyRect, p);
    canvas.drawArc(Rect.fromCircle(center: Offset(left + 140, baseY - 90),
        radius: 62), math.pi, math.pi, true, p);
    tower(left + 10, 16, 150);
    tower(left + 250, 16, 130);
    tower(left + 100, 12, 120);

    // Пальмы правее — на образцах они отделяют мечеть от текста.
    void palm(double x, double h) {
      canvas.drawRect(Rect.fromLTWH(x, baseY - h, 7, h), p);
      for (var i = -2; i <= 2; i++) {
        final path = Path()
          ..moveTo(x + 3, baseY - h)
          ..quadraticBezierTo(x + 3 + i * 26, baseY - h - 34,
              x + 3 + i * 46, baseY - h + (i.abs() * 8) - 6);
        canvas.drawPath(
            path, Paint()..color = _CertColors.goldSoft
              ..style = PaintingStyle.stroke
              ..strokeWidth = 7);
      }
    }

    palm(left + 330, 110);
    palm(left + 400, 80);
  }

  /// Двойная золотая рамка подарочного бланка.
  void _frame(Canvas canvas, Size size, Paint p) {
    final outer = Paint()
      ..color = _CertColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    final inner = Paint()
      ..color = _CertColors.goldSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect(
        Rect.fromLTWH(34, 34, size.width - 68, size.height - 68), outer);
    canvas.drawRect(
        Rect.fromLTWH(52, 52, size.width - 104, size.height - 104), inner);
    // Уголок-лента, как на образце.
    final ribbon = Path()
      ..moveTo(34, 34)
      ..lineTo(210, 34)
      ..lineTo(34, 210)
      ..close();
    canvas.drawPath(ribbon, Paint()..color = _CertColors.gold);
    canvas.drawPath(
        Path()
          ..moveTo(70, 34)
          ..lineTo(210, 34)
          ..lineTo(70, 174)
          ..close(),
        Paint()..color = _CertColors.goldSoft);
  }

  @override
  bool shouldRepaint(covariant _Ornament old) => old.gift != gift;
}

/// Арка с полумесяцем — узнаваемая часть присланных бланков. Рисуется в
/// своей коробке над заголовком, а не поверх всего листа.
class _Arch extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final stroke = Paint()
      ..color = _CertColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final baseY = size.height - 6;

    canvas.drawArc(Rect.fromCircle(center: Offset(cx, baseY - 34), radius: 86),
        math.pi, math.pi, false, stroke);
    canvas.drawArc(
        Rect.fromCircle(center: Offset(cx - 104, baseY - 16), radius: 42),
        math.pi, math.pi, false, stroke);
    canvas.drawArc(
        Rect.fromCircle(center: Offset(cx + 104, baseY - 16), radius: 42),
        math.pi, math.pi, false, stroke);
    canvas.drawLine(Offset(cx - 146, baseY - 16), Offset(cx - 146, baseY),
        stroke);
    canvas.drawLine(Offset(cx + 146, baseY - 16), Offset(cx + 146, baseY),
        stroke);

    // Полумесяц над аркой: круг с вырезом, а не серп из двух дуг —
    // накладывающиеся дуги давали грязный контур.
    final c = Offset(cx, baseY - 132);
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: c, radius: 24)),
      Path()..addOval(Rect.fromCircle(center: c.translate(9, -3), radius: 21)),
    );
    canvas.drawPath(moon, Paint()..color = _CertColors.gold);

    // Звёздочки по бокам — мелкая деталь образца.
    for (final d in [-1.0, 1.0]) {
      final p0 = c.translate(d * 74, 34);
      for (var i = 0; i < 4; i++) {
        final a = math.pi / 2 * i;
        canvas.drawLine(p0, p0.translate(math.cos(a) * 9, math.sin(a) * 9),
            Paint()
              ..color = _CertColors.gold
              ..strokeWidth = 2.4
              ..strokeCap = StrokeCap.round);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Arch old) => false;
}
