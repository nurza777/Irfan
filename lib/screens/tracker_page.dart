import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../services/prayer_service.dart';
import '../services/tracker_service.dart';
import '../theme.dart';

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
            const Text('Трекер намаза',
                style:
                    TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            Text(
              DateFormat('d MMMM, EEEE', 'ru').format(state.now),
              style: TextStyle(
                  fontSize: 15, color: Colors.white.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                color: AppColors.cardGlass,
                child: Column(
                  children: [
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Последние 7 дней',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _WeekStrip(tracker: tracker, now: state.now),
            const Spacer(),
            Center(
              child: Text(
                'Свайп вправо — на главный экран',
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
                Text(prayer.titleRu,
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
            Text('ещё не время',
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
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        icon,
        size: 30,
        color: active
            ? activeColor
            : Colors.white.withValues(alpha: 0.35),
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
        for (final d in days)
          Column(
            children: [
              Text(DateFormat('E', 'ru').format(d),
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7))),
              const SizedBox(height: 6),
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tracker.readCount(d) == 5
                      ? AppColors.accentGreen
                      : AppColors.cardGlass,
                  border: Border.all(
                      color: d.day == now.day
                          ? AppColors.gold
                          : Colors.transparent,
                      width: 1.5),
                ),
                child: Text('${tracker.readCount(d)}/5',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
      ],
    );
  }
}
