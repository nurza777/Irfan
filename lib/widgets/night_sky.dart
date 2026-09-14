import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Фон по умолчанию: ночное небо с силуэтом купола и минаретов.
///
/// Рисуется кодом, а не картинкой, по двум причинам. Первая — права: прежним
/// фоном была фотография Каабы неизвестного происхождения, а доказать права
/// на снимок без метаданных нельзя. Вторая — качество: та фотография была
/// 720×1280 и на экране современного телефона растягивалась вчетверо по
/// площади. Векторная отрисовка чётка на любом разрешении и ничего не весит.
///
/// Своё фото пользователь по-прежнему может поставить в настройках — этот
/// фон только тот, что показывается, пока он этого не сделал.
class NightSky extends StatelessWidget {
  const NightSky({super.key});

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _NightSkyPainter(), isComplex: true);
}

class _NightSkyPainter extends CustomPainter {
  const _NightSkyPainter();

  /// Глубокий верх неба: скругляет переход к [AppColors.skyTop], иначе
  /// у статус-бара небо выглядит выцветшим.
  static const _skyDeep = Color(0xFF13303B);

  /// Силуэт. Не чистый чёрный: на фоне зелёного неба он читался бы дырой.
  static const _silhouette = Color(0xFF0B211B);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    _paintSky(canvas, rect);
    _paintStars(canvas, w, h);
    _paintGlow(canvas, w, h);
    _paintSkyline(canvas, w, h);
  }

  void _paintSky(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_skyDeep, AppColors.skyTop, AppColors.skyBottom],
          stops: [0, 0.45, 1],
        ).createShader(rect),
    );
  }

  /// Звёзды. Зерно фиксировано: рисунок неба должен быть одним и тем же при
  /// каждом запуске, иначе фон «мерцает» между экранами.
  void _paintStars(Canvas canvas, double w, double h) {
    final rnd = math.Random(19);
    final paint = Paint();
    for (var i = 0; i < 90; i++) {
      final x = rnd.nextDouble();
      // Ближе к горизонту звёзд меньше — их «съедает» городская засветка.
      final y = math.pow(rnd.nextDouble(), 1.7).toDouble() * 0.62;
      final r = 0.6 + rnd.nextDouble() * 1.5;
      final alpha = 0.18 + rnd.nextDouble() * 0.42;
      paint.color = AppColors.cream.withValues(alpha: alpha * (1 - y / 0.8));
      canvas.drawCircle(Offset(x * w, y * h), r, paint);
    }
  }

  /// Тёплая засветка над горизонтом — свет города под небом.
  void _paintGlow(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.5, h * 0.72);
    final radius = w * 0.9;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.20),
            AppColors.gold.withValues(alpha: 0.06),
            AppColors.gold.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void _paintSkyline(Canvas canvas, double w, double h) {
    // Земля: сплошная тёмная масса внизу с ровным верхом. Первую версию
    // силуэта портила «аркада» из стрельчатых арок — в размер экрана она
    // вырождалась в пилу и читалась горами, а не галереей.
    final ground = h * 0.90;
    final paint = Paint()..color = _silhouette;

    final domeR = w * 0.155;
    final minaretH = h * 0.115;
    final sideDomeR = w * 0.075;

    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, ground);

    _addSideDome(path, cx: w * 0.135, ground: ground, radius: sideDomeR);
    _addMinaret(path, cx: w * 0.285, ground: ground, height: minaretH, w: w);
    _addDome(path, cx: w * 0.5, ground: ground, radius: domeR);
    // Правый минарет чуть ниже левого: строгая симметрия выглядит штампом,
    // небольшая разница читается как настоящая панорама.
    _addMinaret(path,
        cx: w * 0.715, ground: ground, height: minaretH * 0.86, w: w);
    _addSideDome(path, cx: w * 0.865, ground: ground, radius: sideDomeR);

    path
      ..lineTo(w, ground)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(path, paint);

    // Полумесяцы ставятся поверх готового силуэта: вырез внутри общего
    // контура сложился бы с ним в одну фигуру и «съел» просвет.
    _paintCrescent(
        canvas, Offset(w * 0.5, ground - domeR * 1.72 - w * 0.030), w * 0.026);
    _paintCrescent(canvas,
        Offset(w * 0.285, ground - minaretH - w * 0.018), w * 0.013);
    _paintCrescent(canvas,
        Offset(w * 0.715, ground - minaretH * 0.86 - w * 0.018), w * 0.013);
  }

  /// Минарет: ствол, балкон, шатровое навершие.
  void _addMinaret(Path path,
      {required double cx,
      required double ground,
      required double height,
      required double w}) {
    final half = w * 0.013;
    final balcony = w * 0.022;
    final top = ground - height;
    path
      ..lineTo(cx - half, ground)
      ..lineTo(cx - half, top + height * 0.42)
      ..lineTo(cx - balcony, top + height * 0.42)
      ..lineTo(cx - balcony, top + height * 0.34)
      ..lineTo(cx - half * 0.75, top + height * 0.29)
      ..lineTo(cx - half * 0.75, top + height * 0.13)
      // Шатёр навершия.
      ..lineTo(cx, top)
      ..lineTo(cx + half * 0.75, top + height * 0.13)
      ..lineTo(cx + half * 0.75, top + height * 0.29)
      ..lineTo(cx + balcony, top + height * 0.34)
      ..lineTo(cx + balcony, top + height * 0.42)
      ..lineTo(cx + half, top + height * 0.42)
      ..lineTo(cx + half, ground);
  }

  /// Купол-луковица на барабане.
  void _addDome(Path path,
      {required double cx, required double ground, required double radius}) {
    final drum = ground - radius * 0.62;
    path
      ..lineTo(cx - radius, ground)
      ..lineTo(cx - radius, drum)
      // Плечи шире барабана, дальше сходятся к шпилю — форма луковицы.
      ..cubicTo(cx - radius * 1.08, drum - radius * 0.66, cx - radius * 0.60,
          drum - radius * 1.02, cx, drum - radius * 1.10)
      ..cubicTo(cx + radius * 0.60, drum - radius * 1.02, cx + radius * 1.08,
          drum - radius * 0.66, cx + radius, drum)
      ..lineTo(cx + radius, ground);
  }

  /// Малый купол по краям панорамы — полусфера без барабана.
  void _addSideDome(Path path,
      {required double cx, required double ground, required double radius}) {
    path
      ..lineTo(cx - radius, ground)
      ..cubicTo(cx - radius, ground - radius * 1.18, cx + radius,
          ground - radius * 1.18, cx + radius, ground);
  }

  /// Полумесяц: круг минус смещённый круг. Рисуется в отдельном слое —
  /// иначе вычитание затронуло бы весь силуэт под ним.
  void _paintCrescent(Canvas canvas, Offset c, double r) {
    final outer = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final inner = Path()
      ..addOval(Rect.fromCircle(
          center: Offset(c.dx + r * 0.42, c.dy - r * 0.20), radius: r * 0.86));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, inner),
      Paint()..color = AppColors.gold.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _NightSkyPainter oldDelegate) => false;
}
