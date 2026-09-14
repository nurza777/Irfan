import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/lang.dart';
import '../services/prayer_service.dart';
import '../services/settings_service.dart';
import '../services/visual_effects.dart';
import '../theme.dart';
import 'staff/staff_home.dart';
import 'wallpaper_sheet.dart';
import '../services/staff_auth.dart';
import '../widgets/support_section.dart';
import '../widgets/dome_background.dart';
import '../widgets/city_picker.dart';
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
              const FadeSlideIn(
                delay: Duration(milliseconds: 30),
                child: _EffectsCard(),
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
                                    // Быстрые фишки — только начало списка:
                                    // городов теперь полсотни, и стеной из
                                    // них экран настроек не заваливаем.
                                    for (final c in SettingsService.cities
                                        .take(SettingsService.quickCities))
                                      _cityChip(
                                          c,
                                          c.name == s.manualCity.name,
                                          () => state.setManualCity(c)),
                                    // Выбранный не из быстрых (нашли по
                                    // названию или взяли из конца списка)
                                    // всё равно должен быть виден.
                                    if (!SettingsService.cities
                                        .take(SettingsService.quickCities)
                                        .any((c) =>
                                            c.name == s.manualCity.name))
                                      _cityChip(s.manualCity, true, () {}),
                                    _cityChip(
                                        City(t('Другой город…'), 0, 0),
                                        false,
                                        () => _pickCity(context, state)),
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
                delay: const Duration(milliseconds: 320),
                child: GlassCard(
                  radius: 20,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.emoji_events_outlined,
                              size: 20, color: AppColors.gold),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(t('Скрыть меня из таблицы'),
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700)),
                          ),
                          Switch(
                            value: s.hideInRating,
                            activeThumbColor: AppColors.accentGreen,
                            onChanged: (v) => state.setHideInRating(v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.hideInRating
                            ? t('Вас не видно в общем топе. Своё место вы '
                                'по-прежнему видите, очки начисляются как обычно.')
                            : t('В таблице показывается только имя — ни номера, '
                                'ни города, ни возраста.'),
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: Colors.white.withValues(alpha: 0.65)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Раздел сам исчезает, если контакты в панели не заполнены,
              // — поэтому отступ и анимация тоже внутри него.
              const FadeSlideIn(
                delay: Duration(milliseconds: 340),
                child: SupportSection(),
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
                      const _StaffTile(),
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
                        // Вход для устаза, который ещё не входил. Строка
                        // «Кабинет устаза» показывается только вошедшим, и
                        // без этого долгого нажатия войти было бы негде
                        // вовсе — устазы узнают о нём от администратора.
                        onLongPress: () => StaffHome.open(context),
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

  Future<void> _pickCity(BuildContext context, AppState state) async {
    final picked = await showCityPicker(context);
    if (picked != null) await state.setManualCity(picked);
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
  /// Через сколько минут после намаза спрашивать «прочитали?».
  static const _askOptions = [10, 15, 20, 30, 45, 60];

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
          const SizedBox(height: 6),
          const Divider(height: 22, color: Colors.white24),
          // Эфир — отдельным переключателем: время намаза известно заранее и
          // напоминание ставится на телефоне, а эфир начинается когда угодно,
          // и узнать о нём можно только уведомлением с сервера.
          Row(
            children: [
              const Icon(Icons.sensors, size: 20, color: AppColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t('Уведомлять о начале эфира'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              Switch(
                value: s.liveNotificationsEnabled,
                activeThumbColor: AppColors.accentGreen,
                onChanged: (v) async {
                  final result = await state.setLiveNotificationsEnabled(v);
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
            s.liveNotificationsEnabled
                ? t('Придёт уведомление, когда устаз начнёт трансляцию.')
                : t('Эфир начинается в разное время — без уведомления его легко пропустить.'),
            style: TextStyle(
                fontSize: 13, color: Colors.white.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 6),
          const Divider(height: 22, color: Colors.white24),
          // Вопрос после намаза — независим от азана: кто-то не хочет звонка
          // ко времени намаза, но хочет, чтобы потом спросили и можно было
          // отметить, не открывая приложение.
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 20, color: AppColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t('Спрашивать, прочитан ли намаз'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              Switch(
                value: s.askEnabled,
                activeThumbColor: AppColors.accentGreen,
                onChanged: (v) async {
                  final result = await state.setAskEnabled(v);
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
            s.askEnabled
                ? t('Отметить «Да» или «Нет» можно прямо в уведомлении.')
                : t('Отмечать намазы придётся вручную в трекере.'),
            style: TextStyle(
                fontSize: 13, color: Colors.white.withValues(alpha: 0.65)),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: !s.askEnabled
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      // Проверка кнопок «Да»/«Нет». Без неё убедиться, что
                      // они работают, можно только дождавшись времени намаза
                      // и заданной паузы — то есть часами. А кнопки живут
                      // в системном слое: тестами их не покрыть, ломаются
                      // они молча, и однажды уже сломались.
                      OutlinedButton.icon(
                        onPressed: () async {
                          await state.sendAskTest();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(t('Уведомление придёт через 5 секунд. '
                                'Закройте приложение и нажмите «Да» — отметка '
                                'появится в трекере.')),
                            duration: const Duration(seconds: 6),
                          ));
                        },
                        icon: const Icon(Icons.notifications_active_outlined,
                            size: 18),
                        label: Text(t('Проверить уведомление')),
                      ),
                      const SizedBox(height: 14),
                      Text(t('СПРАШИВАТЬ ЧЕРЕЗ'),
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
                          for (final m in _askOptions)
                            _chip(
                              appLang == Lang.ky ? '$m мүн.' : '$m мин',
                              s.askDelayMinutes == m,
                              () => state.setAskDelayMinutes(m),
                            ),
                        ],
                      ),
                    ],
                  ),
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

/// Выбор уровня оформления.
///
/// Стоит в настройках, а не подбирается сам: надёжно отличить слабый телефон
/// от сильного изнутри приложения нечем — модель и объём памяти о плавности
/// говорят мало. Поэтому по умолчанию берётся уровень, безопасный для
/// платформы (на Android — экономный), а решает человек.
class _EffectsCard extends StatefulWidget {
  const _EffectsCard();

  @override
  State<_EffectsCard> createState() => _EffectsCardState();
}

class _EffectsCardState extends State<_EffectsCard> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VisualEffects.instance,
      builder: (context, _) {
        final level = VisualEffects.instance.level;
        return GlassCard(
          radius: 20,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(
                  icon: Icons.auto_awesome_outlined, title: t('Оформление')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SelectPill(
                      label: t('Полное'),
                      selected: level == EffectsLevel.full,
                      onTap: () => VisualEffects.instance
                          .setLevel(EffectsLevel.full),
                      dense: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectPill(
                      label: t('Экономное'),
                      selected: level == EffectsLevel.light,
                      onTap: () => VisualEffects.instance
                          .setLevel(EffectsLevel.light),
                      dense: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                level == EffectsLevel.full
                    ? t('Матовое стекло и живые обои. Красивее, но на слабых '
                        'телефонах приложение может подтормаживать.')
                    : t('Без размытия и движения обоев. Выглядит проще, зато '
                        'листается плавно.'),
                style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
        );
      },
    );
  }
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

/// Строка «Кабинет устаза» — только для тех, кто уже вошёл.
///
/// Раньше она стояла у всех, и посторонний упирался в окно логина. Само по
/// себе это безопасно (пароль заводит администратор), но обычному человеку
/// незачем даже знать, что в приложении есть служебная часть: чем меньше
/// заметна дверь, тем меньше в неё стучат.
///
/// Войти в первый раз можно долгим нажатием на «О приложении» — иначе
/// скрытая строка заперла бы кабинет навсегда.
class _StaffTile extends StatefulWidget {
  const _StaffTile();

  @override
  State<_StaffTile> createState() => _StaffTileState();
}

class _StaffTileState extends State<_StaffTile> {
  @override
  void initState() {
    super.initState();
    // Токен лежит в Keychain: пока его не прочитали, ответ «не устаз» —
    // неправда, а не факт. Поэтому строку рисуем после init(), а на
    // выход из кабинета откликаемся через подписку.
    StaffAuth.instance.addListener(_onChanged);
    StaffAuth.instance.init().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    StaffAuth.instance.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!StaffAuth.instance.isStaff) return const SizedBox.shrink();
    return Column(
      children: [
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
        ListTile(
          leading: const Icon(Icons.school_outlined, color: AppColors.gold),
          title: Text(t('Кабинет устаза')),
          subtitle: Text(t('Эфир, курсы и новости — для преподавателей'),
              style: TextStyle(
                  fontSize: 13, color: Colors.white.withValues(alpha: 0.6))),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onTap: () => StaffHome.open(context),
        ),
      ],
    );
  }
}
