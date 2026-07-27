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
                    for (final k
                        in PrayerKey.values.where((k) => k.isPrayer))
                      _PrayerRow(
                        prayer: k,
                        time: hhmm.format(times[k]),
                        status: tracker.statusOf(times.date, k),
                        // Отметить можно, когда время намаза уже наступило.
                        enabled: !times[k].isAfter(state.now),
                        onChanged: (s) => state.markPrayer(k, s),
                      ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FadeSlideIn(
              delay: const Duration(milliseconds: 280),
              child: Row(
                children: [
                  Text(t('Последние 7 дней'),
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  PressableScale(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PeriodStatsScreen()),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.query_stats,
                            size: 18, color: AppColors.goldLight),
                        const SizedBox(width: 6),
                        Text(t('За период'),
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.goldLight)),
                      ],
                    ),
                  ),
                ],
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
            const Spacer(),
            Center(
              child: FadeSlideIn(
                delay: const Duration(milliseconds: 500),
                offset: Offset.zero,
                child: Text(
                  t('Свайп вправо — на главный экран'),
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.55)),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
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
              color: (active ? AppColors.gold : Colors.white)
                  .withValues(alpha: 0.15),
            ),
            child: Icon(
              active ? Icons.local_fire_department : Icons.bolt_outlined,
              color: active ? AppColors.goldLight : Colors.white70,
              size: 24,
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
                          : 'Серия: $streak ${_daysWord(streak)} подряд')
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

  String _daysWord(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'день';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня';
    return 'дней';
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            Text(t('ещё не время'),
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.45)))
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
