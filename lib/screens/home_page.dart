import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';

import '../app_state.dart';
import '../services/prayer_service.dart';
import '../services/tracker_service.dart';
import '../theme.dart';
import '../widgets/prayer_times_card.dart';
import 'courses_page.dart';

const _hijriMonthsRu = [
  'Мухаррам', 'Сафар', 'Раби уль-авваль', 'Раби ус-сани',
  'Джумада уль-уля', 'Джумада ус-сани', 'Раджаб', 'Шаабан',
  'Рамадан', 'Шавваль', 'Зуль-Каада', 'Зуль-Хиджа',
];

/// Главный экран: шапка с городом и датой хиджры, карточка времён намаза,
/// вопрос трекера и нижняя панель (Трекер · ··· · Коран).
class HomePage extends StatelessWidget {
  final VoidCallback onOpenTracker;
  final VoidCallback onOpenQuran;
  const HomePage(
      {super.key, required this.onOpenTracker, required this.onOpenQuran});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final hijri = HijriCalendar.now();
    final hijriText =
        '${hijri.hDay} ${_hijriMonthsRu[hijri.hMonth - 1]}, ${hijri.hYear}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.7), width: 1.5),
                    color: Colors.black.withValues(alpha: 0.2),
                  ),
                  child: const Icon(Icons.person_outline, color: Colors.white),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.near_me,
                            size: 16, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(state.location.cityName,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Text(
                      hijriText,
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(flex: 3),
            const PrayerTimesCard(),
            const SizedBox(height: 16),
            const _TrackerQuestionBanner(),
            const Spacer(flex: 4),
            _BottomBar(
                onOpenTracker: onOpenTracker, onOpenQuran: onOpenQuran),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

/// «Прочитали ли вы намаз … ?» — появляется через 10 минут после времени.
class _TrackerQuestionBanner extends StatelessWidget {
  const _TrackerQuestionBanner();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final due = state.tracker!.dueQuestion(state.today!, state.now);
    if (due == null) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: AppColors.cardGlass,
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Прочитали ли вы намаз ${due.titleRu}?',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentGreen),
                    onPressed: () =>
                        state.markPrayer(due, PrayerStatus.read),
                    child: const Text('Да, прочитал(а)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    onPressed: () =>
                        state.markPrayer(due, PrayerStatus.missed),
                    child: const Text('Пропустил(а)'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Нижняя панель: Трекер намаза · «···» (курсы и др.) · КОРАН.
class _BottomBar extends StatelessWidget {
  final VoidCallback onOpenTracker;
  final VoidCallback onOpenQuran;
  const _BottomBar(
      {required this.onOpenTracker, required this.onOpenQuran});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundButton(
          icon: Icons.task_alt,
          tooltip: 'Трекер намаза',
          onTap: onOpenTracker,
        ),
        const Spacer(),
        _RoundButton(
          icon: Icons.more_horiz,
          tooltip: 'Ещё',
          onTap: () => _showMoreSheet(context),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onOpenQuran,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.gold, width: 1.2),
            ),
            child: const Text('КОРАН',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: AppColors.cream)),
          ),
        ),
      ],
    );
  }

  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.skyBottom,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.school_outlined,
                  color: AppColors.gold),
              title: const Text('Курсы'),
              subtitle: const Text('Обучение основам религии'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CoursesPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined,
                  color: AppColors.gold),
              title: const Text('Настройки'),
              subtitle: const Text('Скоро'),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.25),
            border: Border.all(color: AppColors.gold, width: 1.2),
          ),
          child: Icon(icon, color: AppColors.cream),
        ),
      ),
    );
  }
}
