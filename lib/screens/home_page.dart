import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';

import '../app_state.dart';
import '../services/lang.dart';
import '../services/date_fmt.dart';
import '../services/prayer_service.dart';
import '../services/tracker_service.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/prayer_times_card.dart';
import 'account_screen.dart';
import 'azkar_screen.dart';
import 'courses_page.dart';
import 'live_screen.dart';
import 'names_screen.dart';
import 'news_screen.dart';
import 'quran_page.dart';
import 'ramadan_screen.dart';
import 'settings_screen.dart';

const _hijriMonthsRu = [
  'Мухаррам', 'Сафар', 'Раби уль-авваль', 'Раби ус-сани',
  'Джумада уль-уля', 'Джумада ус-сани', 'Раджаб', 'Шаабан',
  'Рамадан', 'Шавваль', 'Зуль-Каада', 'Зуль-Хиджа',
];

/// Главный экран: шапка с городом и датой хиджры, карточка времён намаза,
/// вопрос трекера и нижняя панель (Трекер · ··· · Коран).
class HomePage extends StatelessWidget {
  final VoidCallback onOpenTracker;
  final VoidCallback onOpenZikr;
  final VoidCallback onOpenQibla;
  const HomePage(
      {super.key,
      required this.onOpenTracker,
      required this.onOpenZikr,
      required this.onOpenQibla});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final user = state.auth?.current;
    final hijri = HijriCalendar.now();
    // В кыргызском число пишется через дефис — как и в григорианской дате.
    final hijriMonth = t(_hijriMonthsRu[hijri.hMonth - 1]);
    final hijriText = appLang == Lang.ky
        ? '${hijri.hDay}-$hijriMonth, ${hijri.hYear}'
        : '${hijri.hDay} $hijriMonth, ${hijri.hYear}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 8),
            FadeSlideIn(
              offset: const Offset(0, -18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PressableScale(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AccountScreen())),
                    child: GlassCard(
                      radius: 22,
                      blur: 10,
                      darkness: 0.18,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: user == null
                            ? const Icon(Icons.person_outline,
                                color: Colors.white)
                            : Center(
                                child: Text(
                                  user.name.characters.first
                                      .toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.goldLight),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PressableScale(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AccountScreen())),
                    child: GlassCard(
                      radius: 22,
                      blur: 10,
                      darkness: 0.18,
                      child: SizedBox(
                        height: 44,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.monetization_on,
                                  color: AppColors.goldLight, size: 20),
                              const SizedBox(width: 6),
                              Text('${state.coins}',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.cream)),
                            ],
                          ),
                        ),
                      ),
                    ),
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
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Text(
                        fmtDateLong(state.now),
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.85)),
                      ),
                      Text(
                        hijriText,
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.goldLight
                                .withValues(alpha: 0.9)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(flex: 3),
            const FadeSlideIn(
              delay: Duration(milliseconds: 140),
              child: PrayerTimesCard(),
            ),
            const SizedBox(height: 16),
            const FadeSlideIn(
              delay: Duration(milliseconds: 280),
              child: _TrackerQuestionBanner(),
            ),
            const Spacer(flex: 4),
            FadeSlideIn(
              delay: const Duration(milliseconds: 400),
              child: _BottomBar(
                  onOpenTracker: onOpenTracker,
                  onOpenZikr: onOpenZikr,
                  onOpenQibla: onOpenQibla),
            ),
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

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(sizeFactor: anim, child: child),
      ),
      child: due == null
          ? const SizedBox.shrink()
          : GlassCard(
              key: ValueKey(due),
              radius: 18,
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(appLang == Lang.ky ? '${t(due.titleRu)} намазын окудуңузбу?' : 'Прочитали ли вы намаз ${due.titleRu}?',
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
                          child: Text(t('Да, прочитал(а)')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                                color:
                                    Colors.white.withValues(alpha: 0.6)),
                          ),
                          onPressed: () =>
                              state.markPrayer(due, PrayerStatus.missed),
                          child: Text(t('Пропустил(а)')),
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

/// Нижняя панель: Трекер намаза · «···» (зикры, курсы и др.) · КОРАН.
class _BottomBar extends StatelessWidget {
  final VoidCallback onOpenTracker;
  final VoidCallback onOpenZikr;
  final VoidCallback onOpenQibla;
  const _BottomBar(
      {required this.onOpenTracker,
      required this.onOpenZikr,
      required this.onOpenQibla});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundButton(
          icon: Icons.task_alt,
          tooltip: t('Трекер намаза'),
          onTap: onOpenTracker,
        ),
        const Spacer(),
        _RoundButton(
          icon: Icons.more_horiz,
          tooltip: t('Ещё'),
          onTap: () => _showMoreSheet(context),
        ),
        const Spacer(),
        PressableScale(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const QuranPage())),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: AppColors.gold, width: 1.2),
                ),
                child: Text(t('КОРАН'),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: AppColors.cream)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Material(
            color: AppColors.skyBottom.withValues(alpha: 0.82),
            child: SafeArea(
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
                    leading: const Icon(Icons.menu_book_outlined,
                        color: AppColors.gold),
                    title: Text(t('Азкары и дуа')),
                    subtitle: Text(t('Утро/вечер, после намаза, поминания')),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AzkarScreen()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.nightlight_round,
                        color: AppColors.gold),
                    title: Text(t('Рамадан')),
                    subtitle: Text(t('Сухур, ифтар и дни поста')),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RamadanScreen()));
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.sensors,
                        color: Colors.red.shade400),
                    title: Text(t('Прямой эфир')),
                    subtitle: Text(t('Трансляции устаза')),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LiveScreen()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.campaign_outlined,
                        color: AppColors.gold),
                    title: Text(t('Новости')),
                    subtitle: Text(t('Объявления от устаза')),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const NewsScreen()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.explore_outlined,
                        color: AppColors.gold),
                    title: Text(t('Кибла')),
                    subtitle: Text(t('Компас направления на Мекку')),
                    onTap: () {
                      Navigator.pop(ctx);
                      onOpenQibla();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.track_changes,
                        color: AppColors.gold),
                    title: Text(t('Счётчик зикров')),
                    subtitle: Text(t('Тасбих и дневные цели')),
                    onTap: () {
                      Navigator.pop(ctx);
                      onOpenZikr();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.school_outlined,
                        color: AppColors.gold),
                    title: Text(t('Курсы')),
                    subtitle: Text(t('Обучение основам религии')),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const CoursesPage()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.auto_awesome,
                        color: AppColors.gold),
                    title: Text(t('99 имён Аллаха')),
                    subtitle: Text(t('аль-Асма аль-Хусна')),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const NamesScreen()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined,
                        color: AppColors.gold),
                    title: Text(t('Настройки')),
                    subtitle: Text(t('Локация, мазхаб, зикры')),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()));
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
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
      child: PressableScale(
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
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
        ),
      ),
    );
  }
}
