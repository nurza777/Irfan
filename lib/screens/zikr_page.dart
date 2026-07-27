import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../services/voice_service.dart';
import '../services/lang.dart';
import '../services/zikr_service.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'zikr_settings_sheet.dart';

/// Счётчик зикров: выбор зикра, большой круг-счётчик с прогрессом до
/// дневной цели, вибрация при касании и при достижении цели.
class ZikrPage extends StatefulWidget {
  const ZikrPage({super.key});

  @override
  State<ZikrPage> createState() => _ZikrPageState();
}

class _ZikrPageState extends State<ZikrPage> {
  String? _selectedId;

  @override
  void dispose() {
    VoiceService.instance.stop();
    super.dispose();
  }

  Future<void> _tapCounter(AppState state, ZikrGoal goal) async {
    final before = state.zikrs!.countOf(state.todayDate, goal.id);
    await state.incrementZikr(goal.id);
    if (before + 1 == goal.target) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _confirmReset(AppState state, ZikrGoal goal) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.skyBottom,
        title: Text(t('Сбросить счётчик?')),
        content: Text(appLang == Lang.ky
            ? '«${t(goal.title)}» бүгүн нөлдөн башталат.'
            : '«${goal.title}» за сегодня начнётся с нуля.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Отмена'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Сбросить'))),
        ],
      ),
    );
    if (yes == true) await state.resetZikr(goal.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final zikrs = state.zikrs!;
    final goals = zikrs.goals;

    if (goals.isEmpty) {
      return SafeArea(
        child: Center(
          child: FadeSlideIn(
            child: GlassCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t('Нет ни одной цели по зикрам'),
                      style: TextStyle(fontSize: 17)),
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentGreen),
                    onPressed: () => showZikrSettings(context),
                    child: Text(t('Настроить зикры')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final selected = goals
            .where((g) => g.id == _selectedId)
            .firstOrNull ??
        goals.first;
    final count = zikrs.countOf(state.todayDate, selected.id);
    final progress =
        selected.target == 0 ? 0.0 : count / selected.target;
    final done = count >= selected.target;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            FadeSlideIn(
              offset: const Offset(24, 0),
              child: Row(
                children: [
                  Text(t('Зикры'),
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  PressableScale(
                    onTap: () => showZikrSettings(context),
                    child: const GlassCard(
                      radius: 22,
                      blur: 10,
                      darkness: 0.18,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.tune, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            FadeSlideIn(
              offset: const Offset(24, 0),
              delay: const Duration(milliseconds: 90),
              child: Text(
                '${t('Выполнено сегодня')}: '
                '${(zikrs.dayCompletion(state.todayDate) * 100).round()}%',
                style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.8)),
              ),
            ),
            const SizedBox(height: 16),
            FadeSlideIn(
              delay: const Duration(milliseconds: 160),
              child: SizedBox(
                height: 46,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: goals.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final g = goals[i];
                    final c = zikrs.countOf(state.todayDate, g.id);
                    final isSel = g.id == selected.id;
                    final gDone = c >= g.target;
                    return PressableScale(
                      onTap: () {
                        VoiceService.instance.stop();
                        setState(() => _selectedId = g.id);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black
                              .withValues(alpha: isSel ? 0.45 : 0.28),
                          borderRadius: BorderRadius.circular(23),
                          border: Border.all(
                            color: isSel
                                ? AppColors.gold
                                : Colors.white.withValues(alpha: 0.15),
                            width: isSel ? 1.4 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            if (gDone) ...[
                              const Icon(Icons.check_circle,
                                  size: 16,
                                  color: AppColors.accentGreen),
                              const SizedBox(width: 5),
                            ],
                            Text('${t(g.title)} · $c/${g.target}',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isSel
                                        ? AppColors.cream
                                        : Colors.white
                                            .withValues(alpha: 0.85))),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const Spacer(),
            Center(
              child: FadeSlideIn(
                delay: const Duration(milliseconds: 240),
                child: PressableScale(
                  onTap: () => _tapCounter(state, selected),
                  child: SizedBox(
                    width: 290,
                    height: 290,
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      tween: Tween(
                          end: progress.clamp(0.0, 1.0).toDouble()),
                      builder: (context, p, child) => CustomPaint(
                        painter: _RingPainter(progress: p, done: done),
                        child: child,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: GlassCard(
                          radius: 125,
                          darkness: 0.32,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (selected.arabic.isNotEmpty)
                                  Text(selected.arabic,
                                      style: const TextStyle(
                                          fontSize: 22,
                                          color: AppColors.goldLight)),
                                const SizedBox(height: 2),
                                AnimatedSwitcher(
                                  duration:
                                      const Duration(milliseconds: 180),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(
                                    scale: Tween(begin: 1.25, end: 1.0)
                                        .animate(anim),
                                    child: FadeTransition(
                                        opacity: anim, child: child),
                                  ),
                                  child: Text(
                                    '$count',
                                    key: ValueKey(count),
                                    style: const TextStyle(
                                        fontSize: 68,
                                        height: 1.1,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(appLang == Lang.ky ? '${selected.target} ичинен' : 'из ${selected.target}',
                                    style: TextStyle(
                                        fontSize: 15,
                                        color: Colors.white
                                            .withValues(alpha: 0.7))),
                                const SizedBox(height: 6),
                                Text(t(selected.title),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: done
                    ? Row(
                        key: const ValueKey('done'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              size: 18, color: AppColors.accentGreen),
                          const SizedBox(width: 6),
                          Text(t('Цель на сегодня выполнена'),
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white
                                      .withValues(alpha: 0.9))),
                        ],
                      )
                    : Text(t('Касайтесь круга — плюс один'),
                        key: const ValueKey('hint'),
                        style: TextStyle(
                            fontSize: 14,
                            color:
                                Colors.white.withValues(alpha: 0.6))),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                PressableScale(
                  onTap: () => _confirmReset(state, selected),
                  child: const GlassCard(
                    radius: 22,
                    blur: 10,
                    darkness: 0.18,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.refresh,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _ZikrVoiceButton(goal: selected),
                const Spacer(),
                Text(
                  t('Вправо — домой · влево — новости'),
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.55)),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

/// Кнопка озвучки выбранного зикра; во время речи показывает «стоп».
/// Скрыта, если у зикра нет арабского текста (пользовательский без него).
class _ZikrVoiceButton extends StatelessWidget {
  final ZikrGoal goal;
  const _ZikrVoiceButton({required this.goal});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: VoiceService.instance.speakingId,
      builder: (context, speaking, _) {
        final id = 'zikr_${goal.id}';
        final active = speaking == id;
        return PressableScale(
          onTap: () => VoiceService.instance.speak(id, goal.arabic,
              asset: 'audio/zikr/${goal.id}.mp3', fallback: goal.title),
          child: GlassCard(
            radius: 22,
            blur: 10,
            darkness: 0.18,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                  active ? Icons.stop_rounded : Icons.volume_up_rounded,
                  color: AppColors.goldLight,
                  size: 22),
            ),
          ),
        );
      },
    );
  }
}

/// Кольцо прогресса вокруг счётчика: золотая дуга, при выполнении — свечение.
class _RingPainter extends CustomPainter {
  final double progress;
  final bool done;
  _RingPainter({required this.progress, required this.done});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: r);

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..color = Colors.white.withValues(alpha: 0.14),
    );

    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: done
            ? [AppColors.accentGreen, AppColors.goldLight]
            : [AppColors.gold, AppColors.goldLight],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    if (done) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..color = AppColors.accentGreen.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.done != done;
}
