import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../services/lang.dart';
import '../services/date_fmt.dart';
import '../services/prayer_service.dart';
import '../services/tracker_service.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'period_stats_screen.dart';
import 'restore_prayers_screen.dart';

/// Трекер намаза: отметки за сегодня + статистика за неделю.
class TrackerPage extends StatelessWidget {
  const TrackerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final times = state.today!;
    final tracker = state.tracker!;
    final hhmm = DateFormat('HH:mm');

    return SafeArea(
      // На узких и НИЗКИХ экранах (iPhone SE — 667 точек в высоту) всё это
      // не помещается: карточки серии, пяти намазов, восстановления и
      // недельной полосы дают около 830 точек. Столбец переполнялся снизу
      // на 165 точек — полосатой лентой поверх экрана.
      //
      // Прокрутка с минимальной высотой во весь экран: на высоком телефоне
      // ничего не меняется, Spacer по-прежнему прижимает подсказку к низу;
      // на низком — страница просто листается.
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            const SizedBox(height: 16),
            FadeSlideIn(
              offset: const Offset(-24, 0),
              child: Text(t('Трекер намаза'),
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w700)),
            ),
            FadeSlideIn(
              offset: const Offset(-24, 0),
              delay: const Duration(milliseconds: 90),
              child: Text(
                fmtDayWeekday(state.now),
                style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.8)),
              ),
            ),
            const SizedBox(height: 14),
            FadeSlideIn(
              delay: const Duration(milliseconds: 120),
              child: _StreakBar(
                  streak: tracker.currentStreak(),
                  best: tracker.bestStreak()),
            ),
            const SizedBox(height: 16),
            FadeSlideIn(
              delay: const Duration(milliseconds: 160),
              child: GlassCard(
                radius: 20,
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    // Волосяные линии между намазами: без них пять строк
                    // расплывались в одно пятно и глазу не за что зацепиться.
                    for (final (i, k) in PrayerKey.values
                        .where((k) => k.isPrayer)
                        .indexed) ...[
                      if (i > 0)
                        Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: Colors.white.withValues(alpha: 0.08)),
                      _PrayerRow(
                        prayer: k,
                        time: hhmm.format(times[k]),
                        status: tracker.statusOf(times.date, k),
                        // Отметить можно, когда время намаза уже наступило.
                        enabled: !times[k].isAfter(state.now),
                        onChanged: (s) => state.markPrayer(k, s),
                      ),
                    ],
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FadeSlideIn(
              delay: const Duration(milliseconds: 280),
              child: SectionLabel(
                t('Последние 7 дней'),
                trailing: PressableScale(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PeriodStatsScreen()),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.32),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                AppColors.gold.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.query_stats,
                              size: 16, color: AppColors.goldLight),
                          const SizedBox(width: 6),
                          Text(t('За период'),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.goldLight)),
                        ],
                      ),
                    ),
                  ),
              ),
            ),
            const SizedBox(height: 12),
            FadeSlideIn(
              delay: const Duration(milliseconds: 340),
              child: GlassCard(
                radius: 20,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: _WeekStrip(tracker: tracker, now: state.now),
              ),
            ),
            const SizedBox(height: 12),
            // Строка стоит ВСЕГДА, а не только при наличии пропусков: скрытую
            // человек не находит и не знает, что восстановление вообще есть.
            // Сколько пропущено — сразу в подписи, чтобы не открывать зря.
            FadeSlideIn(
              delay: const Duration(milliseconds: 400),
              child: GlassCard(
                radius: 20,
                child: Builder(builder: (context) {
                  final n = tracker.missedPrayers().length;
                  return ListTile(
                    leading: Icon(Icons.history,
                        color: n > 0 ? AppColors.gold : Colors.white54),
                    title: Text(t('Восстановить намазы'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        n > 0
                            ? '${t('Пропущено')}: $n'
                            : t('Пропущенных намазов нет'),
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.6))),
                    trailing: const Icon(Icons.chevron_right,
                        color: Colors.white54),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RestorePrayersScreen())),
                  );
                }),
              ),
            ),
            const Spacer(),
            Center(
              child: FadeSlideIn(
                delay: const Duration(milliseconds: 500),
                offset: Offset.zero,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    t('Свайп вправо — на главный экран'),
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textFaint),
                  ),
                ),
              ),
            ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Плашка серии: сколько дней подряд все 5 намазов + личный рекорд.
class _StreakBar extends StatelessWidget {
  final int streak;
  final int best;
  const _StreakBar({required this.streak, required this.best});

  @override
  Widget build(BuildContext context) {
    final active = streak > 0;
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withValues(alpha: active ? 0.20 : 0.10),
              // Кольцо вместо серого пятна: без серии значок выглядел
              // выключенным элементом, а не приглашением начать.
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: active ? 0.8 : 0.35),
                  width: 1),
            ),
            child: Icon(
              active ? Icons.local_fire_department : Icons.bolt_outlined,
              color: active
                  ? AppColors.goldLight
                  : AppColors.goldLight.withValues(alpha: 0.7),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active
                      ? (appLang == Lang.ky
                          ? '$streak күн катар'
                          : 'Серия: $streak ${daysWord(streak)} подряд')
                      : t('Начните серию'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  active
                      ? (appLang == Lang.ky
                          ? 'Күн сайын 5 намаз. Рекорд: $best'
                          : 'Все 5 намазов каждый день. Рекорд: $best')
                      : t('Отметьте все 5 намазов сегодня'),
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.65)),
                ),
              ],
            ),
          ),
          if (active)
            Text('$streak',
                style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppColors.goldLight)),
        ],
      ),
    );
  }

}

class _PrayerRow extends StatelessWidget {
  final PrayerKey prayer;
  final String time;
  final PrayerStatus status;
  final bool enabled;
  final ValueChanged<PrayerStatus> onChanged;
  const _PrayerRow({
    required this.prayer,
    required this.time,
    required this.status,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t(prayer.titleRu),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                Text(time,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.7))),
              ],
            ),
          ),
          if (!enabled)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(t('ещё не время'),
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textFaint)),
            )
          else ...[
            _StatusButton(
              icon: Icons.check_circle,
              active: status == PrayerStatus.read,
              activeColor: AppColors.accentGreen,
              onTap: () => onChanged(status == PrayerStatus.read
                  ? PrayerStatus.pending
                  : PrayerStatus.read),
            ),
            const SizedBox(width: 8),
            _StatusButton(
              icon: Icons.cancel,
              active: status == PrayerStatus.missed,
              activeColor: Colors.redAccent,
              onTap: () => onChanged(status == PrayerStatus.missed
                  ? PrayerStatus.pending
                  : PrayerStatus.missed),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _StatusButton(
      {required this.icon,
      required this.active,
      required this.activeColor,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedScale(
        scale: active ? 1.12 : 1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: active
                ? [
                    BoxShadow(
                        color: activeColor.withValues(alpha: 0.55),
                        blurRadius: 14),
                  ]
                : const [],
          ),
          child: Icon(
            icon,
            size: 30,
            color: active
                ? activeColor
                : Colors.white.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final TrackerService tracker;
  final DateTime now;
  const _WeekStrip({required this.tracker, required this.now});

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
        7, (i) => DateTime(now.year, now.month, now.day - 6 + i));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final (i, d) in days.indexed)
          FadeSlideIn(
            delay: Duration(milliseconds: 400 + i * 70),
            offset: const Offset(0, 14),
            child: Column(
              children: [
                Text(fmtWeekdayShort(d),
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7))),
                const SizedBox(height: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tracker.readCount(d) == 5
                        ? AppColors.accentGreen
                        : Colors.black.withValues(alpha: 0.3),
                    border: Border.all(
                        color: d.day == now.day
                            ? AppColors.gold
                            : Colors.white.withValues(alpha: 0.12),
                        width: 1.5),
                  ),
                  child: Text('${tracker.readCount(d)}/5',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
