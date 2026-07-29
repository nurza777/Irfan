import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/lang.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../services/prayer_service.dart';
import '../theme.dart';
import 'glass.dart';

/// Стеклянная карточка со временами намаза и зелёной полосой
/// обратного отсчёта до следующего намаза.
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

    return GlassCard(
      radius: 22,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          for (final k in PrayerKey.values)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t(k.titleRu),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (k.isPrayer)
                    _NotifyToggle(prayer: k),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: k == current
                          ? Colors.white.withValues(alpha: 0.92)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 350),
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: k == current ? Colors.black87 : Colors.white,
                      ),
                      child: Text(hhmm.format(times[k])),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          // Полоса обратного отсчёта до следующего намаза.
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.domeGreen, AppColors.accentGreen],
              ),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  const PulsingDot(color: AppColors.goldLight),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t(nextKey.titleRu),
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
          ),
        ],
      ),
    );
  }
}

/// Динамик рядом с намазом: тап включает и выключает напоминание именно
/// об этом намазе. Раньше значок был просто картинкой и ни на что не влиял.
class _NotifyToggle extends StatelessWidget {
  final PrayerKey prayer;
  const _NotifyToggle({required this.prayer});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final settings = state.settings;
    if (settings == null) return const SizedBox(width: 32);

    // Если напоминания выключены целиком, значок приглушён: включать
    // отдельный намаз бессмысленно, пока не поднят общий тумблер.
    final allOn = settings.notificationsEnabled;
    final on = allOn && settings.notifyPrayers.contains(prayer);

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: PressableScale(
        onTap: () async {
          final next = {...settings.notifyPrayers};
          if (on) {
            next.remove(prayer);
          } else {
            next.add(prayer);
          }
          // Первый же включённый намаз поднимает и общий тумблер —
          // иначе тап выглядел бы так, будто ничего не произошло.
          if (!allOn && next.isNotEmpty) {
            final ok = await state.setNotificationsEnabled(true);
            if (!ok) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(t(
                        'Разрешите уведомления для «Ирфан» в настройках iOS'))));
              }
              return;
            }
          }
          await state.setNotifyPrayers(next);
          HapticFeedback.selectionClick();
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            size: 18,
            color: on
                ? AppColors.goldLight
                : Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
