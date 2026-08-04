import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/lang.dart';
import '../services/prayer_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import 'staff/staff_home.dart';
import 'wallpaper_sheet.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import 'zikr_settings_sheet.dart';

/// Настройки: локация (авто/город вручную), мазхаб, метод расчёта
/// времён намаза, зикры.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings!;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(t('Настройки')),
        centerTitle: true,
      ),
      body: DomeBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 66, 20, 24),
            children: [
              FadeSlideIn(
                child: GlassCard(
                  radius: 20,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle(icon: Icons.language, title: t('Язык')),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final l in Lang.values) ...[
                            _choiceTab(l.label, s.lang == l,
                                () => state.setLanguage(l)),
                            if (l != Lang.values.last)
                              const SizedBox(width: 10),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FadeSlideIn(
                delay: const Duration(milliseconds: 60),
                child: GlassCard(
                  radius: 20,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle(
                          icon: Icons.near_me, title: t('Локация')),
                      const SizedBox(height: 4),
                      Text(
                        '${t('Сейчас')}: ${state.location.cityName}',
                        style: TextStyle(
                            fontSize: 14,
                            color:
                                Colors.white.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _choiceTab(
                              t('Автоматически'),
                              s.locationMode == LocationMode.auto,
                              () => state
                                  .setLocationMode(LocationMode.auto)),
                          const SizedBox(width: 10),
                          _choiceTab(
                              t('Выбрать город'),
                              s.locationMode == LocationMode.manual,
                              () => state
                                  .setLocationMode(LocationMode.manual)),
                        ],
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        child: s.locationMode == LocationMode.manual
                            ? Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final c
                                        in SettingsService.cities)
                                      _cityChip(
                                          c,
                                          c.name ==
                                              s.manualCity.name,
                                          () =>
                                              state.setManualCity(c)),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const FadeSlideIn(
                delay: Duration(milliseconds: 90),
                child: _NotificationsCard(),
              ),
              const SizedBox(height: 14),
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: GlassCard(
                  radius: 20,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle(
                          icon: Icons.schedule,
                          title: t('Мазхаб (время Асра)')),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final m in AsrMadhab.values) ...[
                            _choiceTab(t(m.titleRu), s.madhab == m,
                                () => state.setMadhab(m)),
                            if (m != AsrMadhab.values.last)
                              const SizedBox(width: 10),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FadeSlideIn(
                delay: const Duration(milliseconds: 360),
                child: GlassCard(
                  radius: 20,
                  child: Column(
                    children: [
                      ListTile(
                        leading:
                            const Icon(Icons.tune, color: AppColors.gold),
                        title: Text(t('Настройки зикров'),
                            style:
                                TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(t('Цели: какие зикры и сколько раз'),
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.white
                                    .withValues(alpha: 0.6))),
                        trailing: Icon(Icons.chevron_right,
                            color:
                                Colors.white.withValues(alpha: 0.4)),
                        onTap: () => showZikrSettings(context),
                      ),
                      Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.1)),
                      ListTile(
                        leading: const Icon(Icons.wallpaper_outlined,
                            color: AppColors.gold),
                        title: Text(t('Обои')),
                        subtitle: Text(t('Своё фото вместо стандартного')),
                        trailing: const Icon(Icons.chevron_right,
                            color: Colors.white54),
                        onTap: () => showWallpaperSheet(context),
                      ),
                      Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.1)),
                      // Кабинет устаза открыт всем, но пускает только по
                      // логину и паролю от администратора: отдельного
                      // приложения для преподавателей больше нет.
                      ListTile(
                        leading: const Icon(Icons.school_outlined,
                            color: AppColors.gold),
                        title: Text(t('Кабинет устаза')),
                        subtitle: Text(
                            t('Эфир, курсы и новости — для преподавателей'),
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.white
                                    .withValues(alpha: 0.6))),
                        trailing: const Icon(Icons.chevron_right,
                            color: Colors.white54),
                        onTap: () => StaffHome.open(context),
                      ),
                      Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.1)),
                      ListTile(
                        leading: const Icon(Icons.info_outline,
                            color: AppColors.gold),
                        title: Text(t('О приложении')),
                        subtitle: Text(
                            t('Ирфан 1.0.0 — время намаза, трекер, Коран, зикры'),
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.white
                                    .withValues(alpha: 0.6))),
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

  Widget _choiceTab(String text, bool active, VoidCallback onTap) {
    return Expanded(
      child: PressableScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: active ? 0.4 : 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: active
                    ? AppColors.gold
                    : Colors.white.withValues(alpha: 0.15),
                width: active ? 1.4 : 1),
          ),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? AppColors.cream
                      : Colors.white.withValues(alpha: 0.7))),
        ),
      ),
    );
  }

  Widget _cityChip(City c, bool active, VoidCallback onTap) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppColors.selection.withValues(alpha: 0.18)
              : Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active
                  ? AppColors.selection
                  : Colors.white.withValues(alpha: 0.15),
              width: active ? 1.4 : 1),
        ),
        child: Text(t(c.name),
            style: TextStyle(
                fontSize: 13.5,
                color: active ? AppColors.cream : AppColors.textSoft,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }

}

/// Карточка «Напоминания о намазе»: включение, за сколько минут, какие намазы.
class _NotificationsCard extends StatefulWidget {
  const _NotificationsCard();

  @override
  State<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends State<_NotificationsCard> {
  static const _beforeOptions = [0, 5, 10, 15, 30];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings!;
    final on = s.notificationsEnabled;

    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active,
                  size: 20, color: AppColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t('Напоминания о намазе'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              Switch(
                value: on,
                activeThumbColor: AppColors.accentGreen,
                onChanged: (v) async {
                  final result = await state.setNotificationsEnabled(v);
                  if (v && !result && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(t(
                            'Разрешите уведомления для «Ирфан» в настройках iOS'))));
                  }
                },
              ),
            ],
          ),
          Text(
            on
                ? t('Азан-напоминание придёт на выбранные намазы.')
                : t('Включите, чтобы не пропускать время намаза.'),
            style: TextStyle(
                fontSize: 13, color: Colors.white.withValues(alpha: 0.65)),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: !on
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 14),
                      Text(t('НАПОМИНАТЬ'),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: Colors.white.withValues(alpha: 0.5))),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final m in _beforeOptions)
                            _chip(
                              m == 0
                                  ? t('Вовремя')
                                  : (appLang == Lang.ky
                                      ? '$m мүн. мурун'
                                      : 'за $m мин'),
                              s.notifyBeforeMinutes == m,
                              () => state.setNotifyBeforeMinutes(m),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(t('НАМАЗЫ'),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: Colors.white.withValues(alpha: 0.5))),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final k in SettingsService.notifiablePrayers)
                            _chip(
                              t(k.titleRu),
                              s.notifyPrayers.contains(k),
                              () {
                                final set = {...s.notifyPrayers};
                                set.contains(k)
                                    ? set.remove(k)
                                    : set.add(k);
                                state.setNotifyPrayers(set);
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Выбор здесь показывается тем же золотом, что и язык с локацией выше.
  /// Раньше эти пилюли были зелёными, и на одном экране жили два разных
  /// «выбрано».
  Widget _chip(String text, bool active, VoidCallback onTap) =>
      SelectPill(label: text, selected: active, onTap: onTap, dense: true);
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.gold),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
