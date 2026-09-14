import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/visual_effects.dart';
import '../services/wallpaper_service.dart';
import '../theme.dart';
import 'night_sky.dart';

/// Фон приложения: картинка `assets/images/wallpaper.jpg` или фотография,
/// поставленная пользователем, — с затемнением для читаемости и парящими
/// золотыми частицами. [NightSky] остаётся запасным вариантом, если
/// картинка не прочиталась.
///
/// «Кен-бёрнс» приближение оставлено только для пользовательской фотографии.
/// Нарисованный фон построен под размер экрана целиком, и приближать его
/// нечем: масштаб лишь срезал бы минареты по краям.
///
/// В экономном режиме ([VisualEffects]) фон стоит неподвижно и частиц нет:
/// он рисуется на каждом экране приложения, и вечная анимация означает
/// перерисовку всего экрана 60 раз в секунду даже тогда, когда человек просто
/// читает.
class DomeBackground extends StatefulWidget {
  final Widget child;
  const DomeBackground({super.key, required this.child});

  @override
  State<DomeBackground> createState() => _DomeBackgroundState();
}

class _DomeBackgroundState extends State<DomeBackground>
    with TickerProviderStateMixin {
  AnimationController? _zoom;
  AnimationController? _drift;

  @override
  void initState() {
    super.initState();
    VisualEffects.instance.addListener(_onEffectsChanged);
    _syncControllers();
  }

  void _onEffectsChanged() {
    if (!mounted) return;
    setState(_syncControllers);
  }

  /// Контроллеры заводятся только в полном режиме — остановленный, но живой
  /// тикер всё равно держал бы `AnimatedBuilder` в дереве.
  void _syncControllers() {
    if (VisualEffects.instance.animated) {
      _zoom ??= AnimationController(
          vsync: this, duration: const Duration(seconds: 22))
        ..repeat(reverse: true);
      _drift ??=
          AnimationController(vsync: this, duration: const Duration(seconds: 14))
            ..repeat();
    } else {
      _zoom?.dispose();
      _drift?.dispose();
      _zoom = null;
      _drift = null;
    }
  }

  @override
  void dispose() {
    VisualEffects.instance.removeListener(_onEffectsChanged);
    _zoom?.dispose();
    _drift?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WallpaperService.instance,
      builder: (context, _) => _build(WallpaperService.instance.path),
    );
  }

  Widget _build(String? custom) {
    // Растр фона не зависит от кадра анимации: под RepaintBoundary движок
    // рисует его один раз и дальше только двигает готовый слой.
    final background = RepaintBoundary(
      child: custom != null
          ? Image.file(
              File(custom),
              key: ValueKey(custom),
              fit: BoxFit.cover,
              // Файл могли удалить из галереи уже после выбора.
              errorBuilder: (_, _, _) => const NightSky(),
            )
          : Image.asset(
              'assets/images/wallpaper.jpg',
              fit: BoxFit.cover,
              // Если картинки в сборке не окажется — рисуем небо кодом,
              // пустого экрана человек видеть не должен.
              errorBuilder: (_, _, _) => const NightSky(),
            ),
    );

    final zoom = _zoom;
    final drift = _drift;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (zoom == null || custom == null)
          background
        else
          AnimatedBuilder(
            animation: zoom,
            builder: (context, child) {
              final t = Curves.easeInOut.transform(zoom.value);
              return Transform.scale(
                scale: 1.04 + 0.07 * t,
                alignment: Alignment.topCenter,
                child: child,
              );
            },
            child: background,
          ),
        // Затемнение сверху (статус-бар) и снизу (контент).
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Верх затемнён сильнее, чем раньше: фон стал светлым (закатное
              // небо), и на нём терялась самая бледная строка — дата по
              // хиджре под названием города.
              colors: [
                Color(0x8C000000),
                Color(0x40000000),
                Colors.transparent,
                Color(0x2E000000),
                Color(0xA6000000),
              ],
              stops: [0, 0.13, 0.3, 0.62, 1],
            ),
          ),
        ),
        // Парящие золотые частицы. Под RepaintBoundary: без неё их кадр
        // объявлял грязной всю область стопки, вместе с фотографией.
        if (drift != null)
          IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: drift,
                builder: (context, _) => CustomPaint(
                  painter: _ParticlesPainter(drift.value),
                ),
              ),
            ),
          ),
        widget.child,
      ],
    );
  }
}

/// Частица: положение и характер заданы раз и навсегда. Раньше они
/// вычислялись заново на каждом кадре — вместе с новым `Random` и новым
/// `Paint` на каждый кружок, то есть под тысячу лишних объектов в секунду.
class _Particle {
  final double x;
  final double y;
  final double speed;
  final double phase;
  final double radius;
  const _Particle(this.x, this.y, this.speed, this.phase, this.radius);
}

final List<_Particle> _particles = () {
  final rnd = math.Random(7);
  return List<_Particle>.generate(16, (_) {
    final x = rnd.nextDouble();
    final y = rnd.nextDouble();
    final speed = 0.35 + rnd.nextDouble() * 0.65;
    final phase = rnd.nextDouble();
    final radius = 1.2 + rnd.nextDouble() * 2.2;
    return _Particle(x, y, speed, phase, radius);
  });
}();

class _ParticlesPainter extends CustomPainter {
  final double t;
  _ParticlesPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    // Один Paint на все кружки: цвет у него меняется, объект — нет.
    // Размытие маской убрано: на кружке в пару точек его почти не видно, а
    // стоит оно дороже самой отрисовки.
    final paint = Paint();
    for (final p in _particles) {
      final y = ((p.y - t * p.speed) % 1.0 + 1.0) % 1.0;
      final sway = math.sin((t + p.phase) * 2 * math.pi) * 12;
      // Мерцание + гашение у краёв экрана.
      final twinkle = 0.5 + 0.5 * math.sin((t * 3 + p.phase) * 2 * math.pi);
      final edgeFade = (1 - (2 * y - 1).abs()).clamp(0.0, 1.0);
      paint.color = AppColors.goldLight
          .withValues(alpha: 0.10 + 0.25 * twinkle * edgeFade);
      canvas.drawCircle(
        Offset(p.x * size.width + sway, y * size.height),
        p.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter old) => old.t != t;
}
