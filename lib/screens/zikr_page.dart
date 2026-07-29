import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../services/voice_service.dart';
import '../services/lang.dart';
import '../services/private_zikr_service.dart';
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
      child: SingleChildScrollView(
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
            const SizedBox(height: 24),
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
            const SizedBox(height: 14),
            // Личные обеты — под общим счётчиком, отдельным разделом.
            const _PrivateZikrSection(),
            const SizedBox(height: 14),
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

/// Раздел «Закрытые зикры»: личные обеты с планом на день.
///
/// В отличие от общего счётчика здесь не нажимают по разу, а вписывают
/// сделанное числом — оно уходит из остатка, пока тот не обнулится.
class _PrivateZikrSection extends StatelessWidget {
  const _PrivateZikrSection();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final svc = state.privateZikrs;
    if (svc == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final list = svc.all;
        final day = state.todayDate;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline,
                    size: 18, color: AppColors.goldLight),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(t('Закрытые зикры'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                PressableScale(
                  onTap: () => _edit(context, svc),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.add_circle_outline,
                        color: AppColors.gold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  t('Свой обет: название, сколько раз в день и когда напомнить.'),
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.6)),
                ),
              )
            else
              for (final z in list)
                _PrivateZikrTile(
                  zikr: z,
                  done: svc.doneToday(day, z.id),
                  onAdd: () => _addProgress(context, svc, day, z),
                  onEdit: () => _edit(context, svc, existing: z),
                ),
          ],
        );
      },
    );
  }

  /// Диалог «сколько сделал»: вписанное вычитается из остатка.
  Future<void> _addProgress(BuildContext context, PrivateZikrService svc,
      DateTime day, PrivateZikr z) async {
    final left = svc.leftToday(day, z);
    if (left == 0) {
      final again = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.skyBottom,
          title: Text(t('Уже закрыт на сегодня')),
          content: Text(t('Начать счёт заново?')),
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
      if (again == true) await svc.resetToday(day, z);
      return;
    }

    final ctrl = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.skyBottom,
        title: Text(z.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${t('Осталось')}: $left',
                style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '$left',
                labelText: t('Сколько сделали'),
              ),
              onSubmitted: (v) =>
                  Navigator.pop(ctx, int.tryParse(v.trim()) ?? 0),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 0),
              child: Text(t('Отмена'))),
          // Частый случай — дочитал остаток целиком.
          TextButton(
              onPressed: () => Navigator.pop(ctx, left),
              child: Text(t('Всё'))),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text.trim()) ?? 0),
            child: Text(t('Записать')),
          ),
        ],
      ),
    );
    if (n == null || n <= 0) return;
    final rest = await svc.addProgress(day, z, n);
    if (!context.mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(rest == 0
          ? '${z.title} — ${t('закрыт на сегодня')}'
          : '${t('Осталось')}: $rest'),
    ));
  }

  /// Создание и правка обета.
  Future<void> _edit(BuildContext context, PrivateZikrService svc,
      {PrivateZikr? existing}) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final target =
        TextEditingController(text: '${existing?.target ?? 100}');
    var times = [...(existing?.reminders ?? const <ZikrReminder>[])];

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.skyBottom,
          title: Text(existing == null
              ? t('Новый закрытый зикр')
              : t('Закрытый зикр')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: title,
                  decoration: InputDecoration(labelText: t('Название')),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: target,
                  keyboardType: TextInputType.number,
                  decoration:
                      InputDecoration(labelText: t('Сколько раз в день')),
                ),
                const SizedBox(height: 14),
                Text(t('Когда напоминать'),
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (i, r) in times.indexed)
                      InputChip(
                        label: Text(r.label),
                        onDeleted: () =>
                            setLocal(() => times.removeAt(i)),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(t('Время')),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: const TimeOfDay(hour: 9, minute: 0),
                        );
                        if (picked != null) {
                          setLocal(() => times.add(
                              ZikrReminder(picked.hour, picked.minute)));
                        }
                      },
                    ),
                  ],
                ),
                if (times.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      t('Без времени напоминаний не будет — просто счёт.'),
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.5)),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () async {
                  await svc.remove(existing.id);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: Text(t('Удалить'),
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t('Отмена'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t('Сохранить'))),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final name = title.text.trim();
    final n = int.tryParse(target.text.trim()) ?? 0;
    if (name.isEmpty || n <= 0) return;

    if (existing == null) {
      await svc.add(title: name, target: n, reminders: times);
    } else {
      await svc.update(
          existing.copyWith(title: name, target: n, reminders: times));
    }
    // Напоминания меняются вместе с обетом.
    if (context.mounted) {
      await AppScope.of(context).rescheduleNotifications();
    }
  }
}

class _PrivateZikrTile extends StatelessWidget {
  final PrivateZikr zikr;
  final int done;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  const _PrivateZikrTile({
    required this.zikr,
    required this.done,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final left = (zikr.target - done).clamp(0, zikr.target);
    final closed = left == 0;
    final p = zikr.target == 0 ? 0.0 : done / zikr.target;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableScale(
        onTap: onAdd,
        child: GlassCard(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Icon(closed ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: closed
                      ? AppColors.accentGreen
                      : Colors.white.withValues(alpha: 0.5),
                  size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(zikr.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: p.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation(closed
                            ? AppColors.accentGreen
                            : AppColors.goldLight),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      closed
                          ? t('закрыт на сегодня')
                          : '$done / ${zikr.target} · ${t('осталось')} $left',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.65)),
                    ),
                    if (zikr.reminders.isNotEmpty)
                      Text(
                        zikr.reminders.map((r) => r.label).join(' · '),
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.goldLight
                                .withValues(alpha: 0.8)),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: Icon(Icons.more_horiz,
                    color: Colors.white.withValues(alpha: 0.6), size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
