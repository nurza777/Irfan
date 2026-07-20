import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Фон в стиле дизайна: небо, зелёный купол с золотым шпилем и кирпичное
/// основание. Рисуется кодом, чтобы не тянуть тяжёлую фотографию.
class DomeBackground extends StatelessWidget {
  final Widget child;
  const DomeBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.skyTop, AppColors.skyBottom],
            ),
          ),
        ),
        CustomPaint(painter: _DomePainter()),
        // Затемнение к низу, чтобы контент читался.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.35),
              ],
              stops: const [0.55, 1],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _DomePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.62;
    final domeTop = h * 0.16;
    final domeBase = h * 0.62;
    final domeR = w * 0.55;

    // Кирпичное основание внизу.
    final brickPaint = Paint()..color = AppColors.brick.withValues(alpha: 0.9);
    canvas.drawRect(Rect.fromLTWH(0, domeBase + h * 0.16, w, h), brickPaint);
    final mortar = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 2;
    for (double y = domeBase + h * 0.16; y < h; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(w, y), mortar);
    }

    // Стена под куполом.
    final wallPaint = Paint()..color = AppColors.domeDark;
    canvas.drawRect(
        Rect.fromLTWH(cx - domeR, domeBase, domeR * 2, h * 0.16 + 2), wallPaint);

    // Арки на стене.
    final archPaint = Paint()..color = AppColors.domeGreen.withValues(alpha: 0.75);
    final archW = domeR * 2 / 9;
    for (int i = 0; i < 9; i++) {
      final ax = cx - domeR + archW * i + archW * 0.2;
      final rect = Rect.fromLTWH(ax, domeBase + h * 0.03, archW * 0.6, h * 0.12);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect,
            topLeft: Radius.circular(archW), topRight: Radius.circular(archW)),
        archPaint,
      );
    }

    // Купол.
    final domeRect =
        Rect.fromCenter(center: Offset(cx, domeBase), width: domeR * 2, height: (domeBase - domeTop) * 2);
    final domePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.domeLight, AppColors.domeGreen, AppColors.domeDark],
      ).createShader(domeRect);
    canvas.drawArc(domeRect, math.pi, math.pi, true, domePaint);

    // Рёбра купола.
    final rib = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (double t = -0.8; t <= 0.81; t += 0.2) {
      final path = Path();
      path.moveTo(cx, domeTop);
      path.quadraticBezierTo(
          cx + domeR * t, (domeTop + domeBase) / 2, cx + domeR * t, domeBase);
      canvas.drawPath(path, rib);
    }

    // Золотой ободок у основания купола.
    final goldBand = Paint()
      ..color = AppColors.gold
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(cx - domeR, domeBase), Offset(cx + domeR, domeBase), goldBand);

    // Шпиль с полумесяцем.
    final spirePaint = Paint()
      ..shader = const LinearGradient(
        colors: [AppColors.goldLight, AppColors.gold],
      ).createShader(Rect.fromLTWH(cx - 6, domeTop - h * 0.09, 12, h * 0.09));
    canvas.drawRect(
        Rect.fromLTWH(cx - 2.5, domeTop - h * 0.07, 5, h * 0.07), spirePaint);
    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(
          Offset(cx, domeTop - h * 0.07 + i * 14), 6.0 - i, spirePaint);
    }
    canvas.drawCircle(Offset(cx, domeTop - h * 0.085), 4, spirePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
