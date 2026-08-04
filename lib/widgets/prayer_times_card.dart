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
    final (nextKey, _) = state.nextPrayer();

    return GlassCard(
      radius: 22,
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          for (final k in PrayerKey.values)
            // Идущий сейчас намаз — мягкая зелёная подложка на всю строку.
            // Раньше белой пилюлей подсвечивалось только время: пятно било
            // по глазам и не связывалось с названием слева.
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: k == current
                    ? AppColors.success.withValues(alpha: 0.20)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  if (k == current) ...[
                    const PulsingDot(color: AppColors.goldLight, size: 7),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      t(k.titleRu),
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight:
                              k == current ? FontWeight.w700 : FontWeight.w500,
                          color: k.isPrayer
                              ? Colors.white
                              : AppColors.textSoft),
                    ),
                  ),
                  if (k.isPrayer) _NotifyToggle(prayer: k),
                  Text(
                    hhmm.format(times[k]),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          k == current ? FontWeight.w700 : FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: k == current
                          ? AppColors.goldLight
                          : (k.isPrayer ? Colors.white : AppColors.textSoft),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          // Обратный отсчёт до следующего намаза — часть карточки, а не
          // приклеенная снизу плашка: углы скруглены под её радиус, иначе
          // на стыке торчали прямые края.
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(21)),
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Приглушённый, а не заливка в полную силу: полоса не
                // должна перетягивать внимание с самих времён.
                gradient: LinearGradient(
                  colors: [
                    AppColors.domeDark.withValues(alpha: 0.72),
                    AppColors.accentGreen.withValues(alpha: 0.55),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 11),
                child: Row(
                  children: [
                    Text(
                      t('Следующий'),
                      style: const TextStyle(
                          fontSize: 12,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSoft),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t(nextKey.titleRu),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                    // Единственное место карточки, которое меняется каждую
                    // секунду: перестраивается только эта строка, а не весь
                    // экран (см. AppState.clock).
                    ValueListenableBuilder<DateTime>(
                      valueListenable: state.clock,
                      builder: (_, tick, __) {
                        final left = state.nextPrayer().$2.difference(tick);
                        final h = left.inHours.toString().padLeft(2, '0');
                        final m =
                            (left.inMinutes % 60).toString().padLeft(2, '0');
                        final s =
                            (left.inSeconds % 60).toString().padLeft(2, '0');
                        return Text(
                          '$h:$m:$s',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                            color: AppColors.cream,
                          ),
                        );
                      },
                    ),
                  ],
                ),
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
