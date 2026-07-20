import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../services/prayer_service.dart';
import '../theme.dart';

/// Полупрозрачная карточка со временами намаза и зелёной полосой
/// обратного отсчёта до следующего намаза — как в дизайне.
class PrayerTimesCard extends StatelessWidget {
  const PrayerTimesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final times = state.today!;
    final hhmm = DateFormat('HH:mm');
    final current = times.currentAt(state.now);
    final (nextKey, nextTime) = state.nextPrayer();
    final left = nextTime.difference(state.now);

    String countdown() {
      final h = left.inHours.toString().padLeft(2, '0');
      final m = (left.inMinutes % 60).toString().padLeft(2, '0');
      final s = (left.inSeconds % 60).toString().padLeft(2, '0');
      return '$h:$m:$s';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        color: AppColors.cardGlass,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final k in PrayerKey.values)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        k.titleRu,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (k.isPrayer)
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Icon(Icons.volume_up_rounded,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.55)),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: k == current
                          ? BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Text(
                        hhmm.format(times[k]),
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: k == current ? Colors.black87 : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Container(
              color: AppColors.accentGreen,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      nextKey.titleRu,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    countdown(),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
