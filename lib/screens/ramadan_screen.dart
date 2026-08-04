import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../services/lang.dart';
import '../services/prayer_service.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';

/// Рамадан: время сухура (конец — Фаджр) и ифтара (Магриб), обратный отсчёт
/// до ближайшего события и номер дня поста. Вне Рамадана — сколько до него дней.
class RamadanScreen extends StatelessWidget {
  const RamadanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Экран целиком живёт обратным отсчётом, поэтому подписан на секундные
    // часы напрямую — но только пока открыт (см. AppState.clock).
    final state = AppScope.of(context);
    return ValueListenableBuilder<DateTime>(
      valueListenable: state.clock,
      builder: (context, now, _) => _build(context, state, now),
    );
  }

  Widget _build(BuildContext context, AppState state, DateTime now) {
    final times = state.today!;
    final hijri = HijriCalendar.now();
    final isRamadan = hijri.hMonth == 9;

    final suhoorEnd = times[PrayerKey.fajr]; // сухур до Фаджра
    final iftar = times[PrayerKey.maghrib];

    // Ближайшее событие и время до него.
    final (String label, DateTime target) = _nextEvent(now, suhoorEnd, iftar,
        () => PrayerService.timesFor(
            now.add(const Duration(days: 1)), state.location)[PrayerKey.fajr]);
    final left = target.difference(now);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(t('Рамадан')),
        centerTitle: true,
      ),
      body: DomeBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 70, 20, 24),
            children: [
              FadeSlideIn(
                child: GlassCard(
                  radius: 22,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 22),
                  child: Column(
                    children: [
                      Text(
                        isRamadan
                            ? (appLang == Lang.ky
                                ? 'Орозонун ${hijri.hDay}-күнү'
                                : 'День поста ${hijri.hDay}')
                            : t('До Рамадана'),
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.goldLight),
                      ),
                      const SizedBox(height: 6),
                      if (isRamadan) ...[
                        Text(t(label),
                            style: TextStyle(
                                fontSize: 15,
                                color: Colors.white.withValues(alpha: 0.8))),
                        const SizedBox(height: 8),
                        Text(_fmt(left),
                            style: const TextStyle(
                                fontSize: 46,
                                fontWeight: FontWeight.w800,
                                fontFeatures: [FontFeature.tabularFigures()])),
                      ] else
                        Text(appLang == Lang.ky
                                ? '${_daysUntilRamadan(now)} күн'
                                : '${_daysUntilRamadan(now)} дн.',
                            style: const TextStyle(
                                fontSize: 46, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: Row(
                  children: [
                    Expanded(
                      child: _TimeCard(
                        icon: Icons.nightlight_round,
                        label: t('Сухур до'),
                        time: DateFormat('HH:mm').format(suhoorEnd),
                        hint: t('Конец приёма пищи (Фаджр)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimeCard(
                        icon: Icons.restaurant,
                        label: t('Ифтар'),
                        time: DateFormat('HH:mm').format(iftar),
                        hint: t('Разговение (Магриб)'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FadeSlideIn(
                delay: const Duration(milliseconds: 220),
                child: GlassCard(
                  radius: 18,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_stories,
                          color: AppColors.gold, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          t('Дуа на ифтар: «Аллахумма ляка сумту ва ‘аля '
                              'ризкыка афтарту» — О Аллах, ради Тебя я постился '
                              'и Твоим пропитанием разговляюсь.'),
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String, DateTime) _nextEvent(DateTime now, DateTime suhoorEnd,
      DateTime iftar, DateTime Function() tomorrowFajr) {
    if (now.isBefore(suhoorEnd)) return ('До конца сухура', suhoorEnd);
    if (now.isBefore(iftar)) return ('До ифтара', iftar);
    return ('До сухура', tomorrowFajr());
  }

  String _fmt(Duration d) {
    if (d.isNegative) return '00:00:00';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  int _daysUntilRamadan(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    for (var i = 0; i <= 400; i++) {
      final h = HijriCalendar.fromDate(today.add(Duration(days: i)));
      if (h.hMonth == 9 && h.hDay == 1) return i;
    }
    return 0;
  }
}

class _TimeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String time;
  final String hint;
  const _TimeCard(
      {required this.icon,
      required this.label,
      required this.time,
      required this.hint});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.goldLight, size: 22),
          const SizedBox(height: 10),
          Text(t(label),
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.7))),
          Text(time,
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(hint,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}
