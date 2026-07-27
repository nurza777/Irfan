import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../app_state.dart';
import '../services/lang.dart';
import '../theme.dart';
import '../widgets/glass.dart';

/// Кибла — координаты Каабы в Мекке.
const _kaabaLat = 21.4225;
const _kaabaLon = 39.8262;

/// Компас Киблы: стрелка показывает направление на Каабу с учётом
/// поворота телефона; при точном наведении — золотое свечение и вибрация.
class QiblaPage extends StatefulWidget {
  const QiblaPage({super.key});

  @override
  State<QiblaPage> createState() => _QiblaPageState();
}

class _QiblaPageState extends State<QiblaPage> {
  StreamSubscription<CompassEvent>? _sub;
  double? _heading;
  bool _wasAligned = false;

  @override
  void initState() {
    super.initState();
    _sub = FlutterCompass.events?.listen((e) {
      if (!mounted) return;
      setState(() => _heading = e.heading);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Азимут на Каабу из точки (началная точка — текущая локация).
  double _qiblaBearing(double lat, double lon) {
    final f1 = lat * math.pi / 180;
    final f2 = _kaabaLat * math.pi / 180;
    final dl = (_kaabaLon - lon) * math.pi / 180;
    final y = math.sin(dl) * math.cos(f2);
    final x = math.cos(f1) * math.sin(f2) -
        math.sin(f1) * math.cos(f2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Расстояние до Мекки, км.
  double _distanceKm(double lat, double lon) {
    const r = 6371.0;
    final f1 = lat * math.pi / 180;
    final f2 = _kaabaLat * math.pi / 180;
    final df = (_kaabaLat - lat) * math.pi / 180;
    final dl = (_kaabaLon - lon) * math.pi / 180;
    final a = math.sin(df / 2) * math.sin(df / 2) +
        math.cos(f1) * math.cos(f2) * math.sin(dl / 2) * math.sin(dl / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final loc = state.location;
    final bearing = _qiblaBearing(loc.latitude, loc.longitude);
    final distance = _distanceKm(loc.latitude, loc.longitude);
    final heading = _heading;

    // Насколько телефон отклонён от Киблы.
    double? diff;
    bool aligned = false;
    if (heading != null) {
      diff = ((bearing - heading + 540) % 360) - 180;
      aligned = diff.abs() < 5;
      if (aligned && !_wasAligned) HapticFeedback.mediumImpact();
      _wasAligned = aligned;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            FadeSlideIn(
              offset: const Offset(-24, 0),
              child: Text(t('Кибла'),
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w700)),
            ),
            FadeSlideIn(
              offset: const Offset(-24, 0),
              delay: const Duration(milliseconds: 90),
              child: Text(
                '${t(loc.cityName)} → ${t('Мекка')} · ${distance.round()} км',
                style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.8)),
              ),
            ),
            const Spacer(),
            // Градус направления — над компасом.
            Center(
              child: FadeSlideIn(
                delay: const Duration(milliseconds: 140),
                child: Column(
                  children: [
                    Text(
                      '${bearing.round()}°',
                      style: TextStyle(
                        fontSize: 56,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        color: aligned
                            ? AppColors.accentGreen
                            : AppColors.goldLight,
                        shadows: [
                          Shadow(
                              color: (aligned
                                      ? AppColors.accentGreen
                                      : AppColors.gold)
                                  .withValues(alpha: 0.5),
                              blurRadius: 18),
                        ],
                      ),
                    ),
                    Text(
                      heading == null
                          ? t('направление на Киблу')
                          : aligned
                              ? t('вы направлены на Киблу')
                              : diff! > 0
                                  ? t('поверните вправо')
                                  : t('поверните влево'),
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: FadeSlideIn(
                delay: const Duration(milliseconds: 220),
                child: SizedBox(
                  width: 316,
                  height: 316,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // Свечение при наведении на Киблу.
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: 316,
                        height: 316,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: aligned
                              ? [
                                  BoxShadow(
                                      color: AppColors.accentGreen
                                          .withValues(alpha: 0.45),
                                      blurRadius: 42),
                                ]
                              : [
                                  BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.35),
                                      blurRadius: 30),
                                ],
                        ),
                      ),
                      GlassCard(
                        radius: 158,
                        darkness: 0.32,
                        child: SizedBox(
                          width: 316,
                          height: 316,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Роза компаса вращается против поворота телефона.
                              Transform.rotate(
                                angle: -(heading ?? 0) * math.pi / 180,
                                child: CustomPaint(
                                  size: const Size(292, 292),
                                  painter: _RosePainter(),
                                ),
                              ),
                              // Стрелка на Киблу — крутится, Кааба на месте.
                              Transform.rotate(
                                angle: ((bearing - (heading ?? 0)) *
                                    math.pi /
                                    180),
                                child: CustomPaint(
                                  size: const Size(292, 292),
                                  painter:
                                      _QiblaNeedlePainter(aligned: aligned),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Кааба — неподвижная цель наверху: наведите стрелку.
                      Align(
                        alignment: Alignment.topCenter,
                        child: Transform.translate(
                          offset: const Offset(0, -26),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.skyBottom
                                  .withValues(alpha: 0.9),
                              border: Border.all(
                                  color: aligned
                                      ? AppColors.accentGreen
                                      : AppColors.gold,
                                  width: 2),
                              boxShadow: [
                                BoxShadow(
                                    color: (aligned
                                            ? AppColors.accentGreen
                                            : AppColors.gold)
                                        .withValues(
                                            alpha:
                                                aligned ? 0.6 : 0.3),
                                    blurRadius: aligned ? 22 : 10),
                              ],
                            ),
                            child: const Center(
                              child: Text('🕋',
                                  style: TextStyle(fontSize: 26)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: aligned
                    ? Row(
                        key: const ValueKey('ok'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              size: 18, color: AppColors.accentGreen),
                          const SizedBox(width: 6),
                          Text(t('Можно совершать намаз'),
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white
                                      .withValues(alpha: 0.9))),
                        ],
                      )
                    : Text(
                        heading == null
                            ? t('Компас появится на телефоне — на симуляторе датчика нет')
                            : t('Держите телефон горизонтально'),
                        key: const ValueKey('hint'),
                        style: TextStyle(
                            fontSize: 13,
                            color:
                                Colors.white.withValues(alpha: 0.6)),
                      ),
              ),
            ),
            const Spacer(),
            Center(
              child: Text(
                t('Свайп влево — трекер намаза'),
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.55)),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

/// Роза компаса: восьмиконечная звезда, градуировка с цифрами,
/// стороны света и метка севера.
class _RosePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    // Лёгкая виньетка по краю.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.3),
          ],
          stops: const [0.72, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Двойной золотой ободок.
    canvas.drawCircle(
        c,
        r - 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.gold.withValues(alpha: 0.5));
    canvas.drawCircle(
        c,
        r - 24,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = AppColors.gold.withValues(alpha: 0.25));

    // Восьмиконечная звезда (хатам) — два повёрнутых квадрата.
    Path square(double rot) {
      final p = Path();
      for (int i = 0; i < 4; i++) {
        final a = rot + i * math.pi / 2;
        final pt = c + Offset(math.sin(a), -math.cos(a)) * (r * 0.52);
        if (i == 0) {
          p.moveTo(pt.dx, pt.dy);
        } else {
          p.lineTo(pt.dx, pt.dy);
        }
      }
      return p..close();
    }

    for (final rot in [0.0, math.pi / 4]) {
      canvas.drawPath(
        square(rot),
        Paint()
          ..shader = RadialGradient(
            colors: [
              AppColors.gold.withValues(alpha: 0.16),
              AppColors.gold.withValues(alpha: 0.04),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r * 0.55)),
      );
      canvas.drawPath(
        square(rot),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.gold.withValues(alpha: 0.28),
      );
    }

    // Градуировка: тонкие деления каждые 5°, средние 15°, золотые 45°.
    for (int deg = 0; deg < 360; deg += 5) {
      final rad = deg * math.pi / 180;
      final major = deg % 45 == 0;
      final mid = deg % 15 == 0;
      final len = major ? 15.0 : (mid ? 10.0 : 5.0);
      final p = Paint()
        ..color = major
            ? AppColors.gold
            : Colors.white.withValues(alpha: mid ? 0.4 : 0.16)
        ..strokeWidth = major ? 2.2 : (mid ? 1.4 : 1)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        c + Offset(math.sin(rad), -math.cos(rad)) * (r - 6 - len),
        c + Offset(math.sin(rad), -math.cos(rad)) * (r - 6),
        p,
      );
    }

    // Цифры градусов каждые 30° (кроме сторон света).
    for (int deg = 30; deg < 360; deg += 30) {
      if (deg % 90 == 0) continue;
      final rad = deg * math.pi / 180;
      final tp = TextPainter(
        text: TextSpan(
          text: '$deg',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.45)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pos = c +
          Offset(math.sin(rad), -math.cos(rad)) * (r - 34) -
          Offset(tp.width / 2, tp.height / 2);
      tp.paint(canvas, pos);
    }

    // Метка севера — золотой треугольник.
    final northTip = Path()
      ..moveTo(c.dx, c.dy - r + 24)
      ..lineTo(c.dx - 6, c.dy - r + 36)
      ..lineTo(c.dx + 6, c.dy - r + 36)
      ..close();
    canvas.drawPath(northTip, Paint()..color = AppColors.goldLight);

    // Стороны света.
    final dirs = appLang == Lang.ky
        ? const ['Түн', 'Чыг', 'Түш', 'Бат']
        : const ['С', 'В', 'Ю', 'З'];
    for (int i = 0; i < 4; i++) {
      final rad = i * math.pi / 2;
      final tp = TextPainter(
        text: TextSpan(
          text: dirs[i],
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: i == 0 ? AppColors.goldLight : AppColors.cream,
            shadows: [
              Shadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 4),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pos = c +
          Offset(math.sin(rad), -math.cos(rad)) * (r - 50) -
          Offset(tp.width / 2, tp.height / 2);
      tp.paint(canvas, pos);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Стрелка на Киблу: объёмный ромб (свет/тень) с хвостом-противовесом.
class _QiblaNeedlePainter extends CustomPainter {
  final bool aligned;
  _QiblaNeedlePainter({required this.aligned});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final color = aligned ? AppColors.accentGreen : AppColors.gold;
    final light = aligned ? const Color(0xFF57D690) : AppColors.goldLight;
    final dark = aligned ? const Color(0xFF1E7A4C) : const Color(0xFF9A7A2F);

    final tipY = c.dy - r + 32;
    final waistY = c.dy - r * 0.30;
    final tailY = c.dy + r * 0.30;

    // Тень под стрелкой.
    final shadow = Path()
      ..moveTo(c.dx + 2, tipY + 3)
      ..lineTo(c.dx - 9, waistY + 3)
      ..lineTo(c.dx + 2, tailY + 3)
      ..lineTo(c.dx + 13, waistY + 3)
      ..close();
    canvas.drawPath(
      shadow,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Хвост-противовес (ромб к югу), полупрозрачное стекло.
    final tailPath = Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx - 8, c.dy + (tailY - c.dy) * 0.45)
      ..lineTo(c.dx, tailY)
      ..lineTo(c.dx + 8, c.dy + (tailY - c.dy) * 0.45)
      ..close();
    canvas.drawPath(
        tailPath, Paint()..color = Colors.white.withValues(alpha: 0.28));
    canvas.drawPath(
      tailPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.45),
    );

    // Остриё к Каабе — ромб из двух половин (свет/тень) для объёма.
    final leftHalf = Path()
      ..moveTo(c.dx, tipY)
      ..lineTo(c.dx - 11, waistY)
      ..lineTo(c.dx, c.dy)
      ..close();
    final rightHalf = Path()
      ..moveTo(c.dx, tipY)
      ..lineTo(c.dx + 11, waistY)
      ..lineTo(c.dx, c.dy)
      ..close();
    canvas.drawPath(leftHalf, Paint()..color = dark);
    canvas.drawPath(
      rightHalf,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light, color],
        ).createShader(Rect.fromLTRB(c.dx, tipY, c.dx + 11, c.dy)),
    );
    if (aligned) {
      canvas.drawPath(
        Path.from(leftHalf)..addPath(rightHalf, Offset.zero),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8),
      );
    }

    // Ось: золотое кольцо с тёмной серединой и бликом.
    canvas.drawCircle(
      c,
      11,
      Paint()
        ..shader = RadialGradient(
          colors: [light, color, dark],
          stops: const [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: c, radius: 11)),
    );
    canvas.drawCircle(c, 5, Paint()..color = AppColors.skyBottom);
    canvas.drawCircle(Offset(c.dx - 2, c.dy - 2), 1.5,
        Paint()..color = Colors.white.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(covariant _QiblaNeedlePainter old) =>
      old.aligned != aligned;
}
