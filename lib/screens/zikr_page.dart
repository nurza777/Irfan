import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../services/private_zikr_service.dart';
import '../services/voice_service.dart';
import 'private_zikr_section.dart';
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
  /// Ключи пилюль в ленте — чтобы при переключении стрелками довести
  /// выбранный зикр до видимой части: иначе он уезжает за край и кажется,
  /// что не выбрано ничего.
  final _chipKeys = <String, GlobalKey>{};

  void _revealSelected(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chipKeys[id]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          alignment: 0.5);
    });
  }

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

  /// Следующий или предыдущий зикр по кругу: с последнего попадаем на
  /// первый, иначе стрелка выглядела бы сломанной на краях списка.
  void _step(List<ZikrGoal> goals, ZikrGoal current, int delta) {
    if (goals.length < 2) return;
    final i = goals.indexWhere((g) => g.id == current.id);
    final next = goals[(i + delta + goals.length) % goals.length];
    VoiceService.instance.stop();
    HapticFeedback.selectionClick();
    setState(() => _selectedId = next.id);
    _revealSelected(next.id);
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

    // Закрытые зикры показываем в том же ряду названий: раньше о них
    // напоминал только раздел в настройках, и про добавленный обет легко
    // было забыть. Считаются они по-прежнему вводом числа — круг с
    // нажатиями для обета не подходит.
    final private = state.privateZikrs?.all ?? const <PrivateZikr>[];

    final selected = goals
            .where((g) => g.id == _selectedId)
            .firstOrNull ??
        goals.first;
    final count = zikrs.countOf(state.todayDate, selected.id);
    final progress =
        selected.target == 0 ? 0.0 : count / selected.target;
    final done = count >= selected.target;

    return SafeArea(
      // Экран должен занимать высоту целиком: содержимого немного, и в
      // обычном скролле оно жалось к верху, оставляя внизу пустое поле обоев.
      // minHeight растягивает колонку на весь видимый экран, а прокрутка
      // остаётся на случай мелкого телефона или крупного системного шрифта.
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
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
                  itemCount: goals.length + private.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    // Обеты идут ПЕРВЫМИ: постоянных зикров семь, ряд
                    // прокручивается, и в хвосте свой обет не виден — а он
                    // как раз тот, о котором забываешь.
                    if (i < private.length) {
                      return _PrivateChip(zikr: private[i]);
                    }
                    final g = goals[i - private.length];
                    final c = zikrs.countOf(state.todayDate, g.id);
                    final isSel = g.id == selected.id;
                    final gDone = c >= g.target;
                    return PressableScale(
                      key: _chipKeys.putIfAbsent(g.id, GlobalKey.new),
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
            const Spacer(flex: 2),
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
            const SizedBox(height: 14),
            // Стрелки под кругом листают зикры. Лента сверху для этого
            // требует прицелиться в нужную пилюлю, а тут палец уже рядом
            // с кругом — переключился и считаешь дальше.
            Row(
              children: [
                _ArrowButton(
                  icon: Icons.chevron_left,
                  enabled: goals.length > 1,
                  onTap: () => _step(goals, selected, -1),
                ),
                Expanded(
                  child: Center(
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
                                Flexible(
                                  child: Text(t('Цель выполнена'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontSize: 13.5,
                                          color: AppColors.textSoft)),
                                ),
                              ],
                            )
                          : Text(t('Касайтесь круга — плюс один'),
                              key: const ValueKey('hint'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  color: AppColors.textFaint)),
                    ),
                  ),
                ),
                _ArrowButton(
                  icon: Icons.chevron_right,
                  enabled: goals.length > 1,
                  onTap: () => _step(goals, selected, 1),
                ),
              ],
            ),
            const Spacer(flex: 3),
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
          ),
        ),
      ),
    );
  }
}

/// Круглая стрелка переключения зикра.
/// Закрытый зикр в ряду названий. Отличается замком и тем, что по нажатию
/// открывает ввод числа, а не встаёт в круг: обет заполняют «сколько
/// сделал», и менять это ради единообразия было бы хуже для человека.
class _PrivateChip extends StatelessWidget {
  final PrivateZikr zikr;
  const _PrivateChip({required this.zikr});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final svc = state.privateZikrs;
    if (svc == null) return const SizedBox.shrink();
    final day = state.todayDate;
    final done = svc.doneToday(day, zikr.id);
    final closed = done >= zikr.target;
    return PressableScale(
      onTap: () {
        VoiceService.instance.stop();
        showPrivateZikrProgress(context, svc, day, zikr);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(closed ? Icons.check_circle : Icons.lock_outline,
                size: 16,
                color: closed ? AppColors.accentGreen : AppColors.goldLight),
            const SizedBox(width: 5),
            Text('${zikr.title} · $done/${zikr.target}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85))),
          ],
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _ArrowButton(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: PressableScale(
        onTap: enabled ? onTap : null,
        child: GlassCard(
          radius: 21,
          blur: 10,
          darkness: 0.2,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: AppColors.goldLight, size: 26),
          ),
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
    // Записи есть не у всех зикров. Мёртвая кнопка хуже её отсутствия.
    if (!VoiceService.instance.hasRecording('audio/zikr/${goal.id}.mp3')) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<String?>(
      valueListenable: VoiceService.instance.speakingId,
      builder: (context, speaking, _) {
        final id = 'zikr_${goal.id}';
        final active = speaking == id;
        return PressableScale(
          onTap: () =>
              VoiceService.instance.speak(id, 'audio/zikr/${goal.id}.mp3'),
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

/// Раздел «Закрытые зикры»: личные обеты с планом на день.
///
/// В отличие от общего счётчика здесь не нажимают по разу, а вписывают
/// сделанное числом — оно уходит из остатка, пока тот не обнулится.
