import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/date_fmt.dart';
import '../services/lang.dart';
import '../services/prayer_service.dart';
import '../services/tracker_service.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';

/// Восстановление пропущенных намазов («каза»).
///
/// Пропуск в трекере до сих пор был приговором: отметил «не прочитал» —
/// и красная отметка оставалась навсегда, даже если человек потом
/// восполнил намаз. Это расходится и с обычаем, и со здравым смыслом:
/// пропущенный намаз положено восстанавливать, а не забывать.
///
/// Восстановленный намаз НЕ приравнивается к прочитанному вовремя. В
/// статистике он идёт отдельной строкой — иначе исчезла бы вся разница
/// между дисциплиной и наверстыванием, а вместе с ней и смысл трекера.
class RestorePrayersScreen extends StatefulWidget {
  const RestorePrayersScreen({super.key});

  @override
  State<RestorePrayersScreen> createState() => _RestorePrayersScreenState();
}

class _RestorePrayersScreenState extends State<RestorePrayersScreen> {
  Future<void> _restore(
      AppState state, MissedPrayer m, TrackerService tracker) async {
    await state.setPrayerStatusOn(m.day, m.prayer, PrayerStatus.restored);
    if (!mounted) return;
    setState(() {});
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(
          '${t(m.prayer.titleRu)} — ${t('восстановлен')}, ${fmtDateShort(m.day)}'),
      // Отметить не тот намаз в длинном списке дат легко, а без отмены
      // исправлять пришлось бы вручную по дням.
      action: SnackBarAction(
        label: t('Отменить'),
        onPressed: () async {
          await state.setPrayerStatusOn(m.day, m.prayer, PrayerStatus.missed);
          if (mounted) setState(() {});
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tracker = state.tracker!;
    final missed = tracker.missedPrayers();

    // Группируем по дню: список идёт датами, а не сплошной лентой намазов.
    final byDay = <String, List<MissedPrayer>>{};
    for (final m in missed) {
      byDay.putIfAbsent(TrackerService.dayKeyOf(m.day), () => []).add(m);
    }

    return Scaffold(
      body: DomeBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(t('Восстановить намазы'),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: missed.isEmpty
                    ? _empty()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: [
                          GlassCard(
                            radius: 16,
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.history,
                                    color: AppColors.gold, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    t('Отметьте намазы, которые вы восполнили. '
                                        'В статистике они будут учтены как '
                                        'восстановленные — отдельно от '
                                        'прочитанных вовремя.'),
                                    style: TextStyle(
                                        fontSize: 13,
                                        height: 1.35,
                                        color: Colors.white
                                            .withValues(alpha: 0.75)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                              '${t('Осталось восстановить')}: ${missed.length}',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          for (final entry in byDay.entries) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(2, 12, 2, 8),
                              child: Text(fmtDateLong(entry.value.first.day),
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white
                                          .withValues(alpha: 0.6))),
                            ),
                            GlassCard(
                              radius: 18,
                              child: Column(
                                children: [
                                  for (var i = 0;
                                      i < entry.value.length;
                                      i++) ...[
                                    if (i > 0)
                                      Divider(
                                          height: 1,
                                          color: Colors.white
                                              .withValues(alpha: 0.1)),
                                    ListTile(
                                      leading: const Icon(Icons.cancel,
                                          color: Colors.redAccent),
                                      title:
                                          Text(t(entry.value[i].prayer.titleRu)),
                                      trailing: TextButton(
                                        onPressed: () => _restore(
                                            state, entry.value[i], tracker),
                                        child: Text(t('Восстановить'),
                                            style: const TextStyle(
                                                color: AppColors.goldLight,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 56, color: Colors.white.withValues(alpha: 0.35)),
              const SizedBox(height: 14),
              Text(t('Пропущенных намазов нет'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
        ),
      );
}
