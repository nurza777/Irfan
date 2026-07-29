import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/wallpaper_service.dart';
import '../theme.dart';

/// Фон приложения: фотография Каабы и часовой башни Мекки с медленным
/// «кен-бёрнс» приближением, затемнением для читаемости и парящими
/// золотыми частицами.
class DomeBackground extends StatefulWidget {
  final Widget child;
  const DomeBackground({super.key, required this.child});

  @override
  State<DomeBackground> createState() => _DomeBackgroundState();
}

class _DomeBackgroundState extends State<DomeBackground>
    with TickerProviderStateMixin {
  late final AnimationController _zoom = AnimationController(
      vsync: this, duration: const Duration(seconds: 22))
    ..repeat(reverse: true);
  late final AnimationController _drift = AnimationController(
      vsync: this, duration: const Duration(seconds: 14))
    ..repeat();

  @override
  void dispose() {
    _zoom.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Фото с медленным приближением/отдалением.
        AnimatedBuilder(
          animation: _zoom,
          builder: (context, child) {
            final t =
                Curves.easeInOut.transform(_zoom.value);
            return Transform.scale(
              scale: 1.04 + 0.07 * t,
              alignment: Alignment.topCenter,
              child: child,
            );
          },
          // Свои обои, если выбраны; иначе встроенное фото Каабы.
          child: ListenableBuilder(
            listenable: WallpaperService.instance,
            builder: (context, _) {
              final custom = WallpaperService.instance.path;
              if (custom != null) {
                return Image.file(
                  File(custom),
                  key: ValueKey(custom),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Image.asset(
                      'assets/images/wallpaper.jpg',
                      fit: BoxFit.cover),
                );
              }
              return Image.asset(
                'assets/images/wallpaper.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: AppColors.skyBottom),
              );
            },
          ),
        ),
        // Затемнение сверху (статус-бар) и снизу (контент).
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x66000000),
                Colors.transparent,
                Color(0x2E000000),
                Color(0xA6000000),
              ],
              stops: [0, 0.22, 0.6, 1],
            ),
          ),
        ),
        // Парящие золотые частицы.
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _drift,
            builder: (context, _) => CustomPaint(
              painter: _ParticlesPainter(_drift.value),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _ParticlesPainter extends CustomPainter {
  final double t;
  _ParticlesPainter(this.t);

  static const _count = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    for (int i = 0; i < _count; i++) {
      final baseX = rnd.nextDouble();
      final baseY = rnd.nextDouble();
      final speed = 0.35 + rnd.nextDouble() * 0.65;
      final phase = rnd.nextDouble();
      final r = 1.2 + rnd.nextDouble() * 2.2;

      final y = ((baseY - t * speed) % 1.0 + 1.0) % 1.0;
      final sway = math.sin((t + phase) * 2 * math.pi) * 12;
      // Мерцание + гашение у краёв экрана.
      final twinkle =
          0.5 + 0.5 * math.sin((t * 3 + phase) * 2 * math.pi);
      final edgeFade =
          (1 - (2 * y - 1).abs()).clamp(0.0, 1.0);
      final alpha = 0.10 + 0.25 * twinkle * edgeFade;

      canvas.drawCircle(
        Offset(baseX * size.width + sway, y * size.height),
        r,
        Paint()
          ..color = AppColors.goldLight.withValues(alpha: alpha)
          ..maskFilter =
              const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter old) => old.t != t;
}
