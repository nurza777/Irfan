import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';

import '../app_state.dart';
import '../services/auth_service.dart';
import '../services/lang.dart';
import '../services/date_fmt.dart';
import '../services/prayer_service.dart';
import '../services/books_service.dart';
import '../services/certificate_service.dart';
import '../services/support_chat_service.dart';
import '../services/tracker_service.dart';
import '../services/visual_effects.dart';
import '../theme.dart';
import '../widgets/account_gate.dart';
import '../widgets/glass.dart';
import '../widgets/prayer_times_card.dart';
import 'account_screen.dart';
import 'azkar_screen.dart';
import 'books_screen.dart';
import 'certificates_screen.dart';
import 'courses_page.dart';
import 'live_screen.dart';
import 'names_screen.dart';
import 'news_screen.dart';
import 'quran_page.dart';
import 'ramadan_screen.dart';
import 'settings_screen.dart';
import 'wallpaper_sheet.dart';

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

    return GestureDetector(
      // Долгое нажатие по пустому месту меняет обои. behavior нужен, чтобы
      // жест ловился и там, где под пальцем нет ни одного виджета.
      behavior: HitTestBehavior.translucent,
      onLongPress: () => showWallpaperSheet(context),
      child: SafeArea(
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
                        width: 38,
                        height: 38,
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
                  // Коины считаются по аккаунту: без него это всегда ноль,
                  // и чип только сбивал бы с толку.
                  if (user != null) ...[
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
                          height: 38,
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 11),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Не доллар: коины — внутренние баллы, а
                                // значок валюты сбивал с толку.
                                const Icon(Icons.toll,
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
                  ],
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
            // Пропорция 2:3 вместо 3:4: сверху остаётся воздух с минаретом,
            // но карточка перестаёт висеть в середине пустого экрана.
            const Spacer(flex: 2),
            const FadeSlideIn(
              delay: Duration(milliseconds: 140),
              child: PrayerTimesCard(),
            ),
            const SizedBox(height: 14),
            const FadeSlideIn(
              delay: Duration(milliseconds: 280),
              child: _TrackerQuestionBanner(),
            ),
            const Spacer(flex: 3),
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
      ),
    );
  }
}

/// Пункт меню «···». [free] — открыт и без аккаунта (кибла, настройки);
/// остальные показываются с замком и ведут на приглашение зарегистрироваться.
///
/// [sheet] — контекст самого листа: его надо закрыть до перехода, иначе
/// новый экран открывается под ним.
class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final BuildContext sheet;
  final void Function(BuildContext context) open;
  final bool free;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.sheet,
    required this.open,
    this.iconColor,
    this.free = false,
    this.badge = 0,
  });

  /// Сколько новых внутри. Пушей у нас нет: точка в меню — единственный
  /// способ сообщить, что документ выдан, не дожидаясь, пока человек сам
  /// заглянет в раздел.
  final int badge;

  @override
  Widget build(BuildContext context) {
    final locked = !free && !AccountGate.isOpen(context);
    final dim = locked ? 0.45 : 1.0;
    return ListTile(
      leading: Icon(icon,
          color: (iconColor ?? AppColors.gold).withValues(alpha: dim)),
      title: Text(t(title),
          style: TextStyle(color: Colors.white.withValues(alpha: dim))),
      subtitle: Text(t(subtitle),
          style: TextStyle(
              color: Colors.white.withValues(alpha: dim * 0.7))),
      trailing: locked
          ? Icon(Icons.lock_outline,
              size: 18, color: Colors.white.withValues(alpha: 0.5))
          : (badge > 0
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$badge',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.black)),
                )
              : null),
      onTap: () {
        final navigatorContext = context;
        Navigator.pop(sheet);
        if (locked) {
          AccountGate.invite(navigatorContext, t(title));
        } else {
          open(navigatorContext);
        }
      },
    );
  }
}

/// «Прочитали ли вы намаз … ?» — появляется через 10 минут после времени.
class _TrackerQuestionBanner extends StatelessWidget {
  const _TrackerQuestionBanner();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    // Ответ уходит в трекер, а трекер — часть аккаунта. Без него спрашивать
    // не о чем: отметка всё равно никуда не запишется.
    if (!AccountGate.isOpen(context)) return const SizedBox.shrink();
    final female = state.auth?.current?.gender == Gender.female;
    final due = state.tracker!.dueQuestion(state.today!, state.now,
        delay: state.settings!.askDelay);

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
                          child: Text(gendered('Да, прочитал(а)',
                              'Да, прочитал', 'Да, прочитала', female)),
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
                          child: Text(gendered('Пропустил(а)',
                              'Пропустил', 'Пропустила', female)),
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
/// Кнопка нижнего ряда: иконка и подпись, одинаковая ширина у всех трёх.
/// [accent] — золотая рамка у главного действия (Коран).
class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VisualEffects.instance,
      builder: (context, _) => _build(VisualEffects.instance.blur),
    );
  }

  Widget _build(bool blurred) {
    // Кнопок в панели три, и они видны на главной всё время — три размытия
    // подряд там, где хватает плотной заливки.
    final base = accent ? 0.30 : 0.24;
    final inner = Container(
            // Иконка и подпись в строку: столбиком кнопка выходила в
            // полсотни точек высотой и занимала низ экрана целиком.
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black
                  .withValues(alpha: blurred ? base : base + 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: accent
                      ? AppColors.gold
                      : Colors.white.withValues(alpha: 0.20),
                  width: accent ? 1.3 : 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 18,
                    color: accent ? AppColors.goldLight : Colors.white),
                const SizedBox(width: 7),
                Text(label,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: accent ? AppColors.cream : AppColors.textSoft)),
              ],
            ),
    );
    return PressableScale(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: blurred
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: inner,
              )
            : inner,
      ),
    );
  }
}

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
    // Три равные кнопки с подписями вместо круг-круг-пилюля: раньше формы
    // и размеры были разные, а «КОРАН» кричал капсом на фоне безымянных
    // иконок — по виду не читалось, что это одного уровня действия.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _BarButton(
          icon: Icons.task_alt,
          label: t('Трекер'),
          onTap: onOpenTracker,
        ),
        _BarButton(
          icon: Icons.grid_view_rounded,
          label: t('Ещё'),
          onTap: () => showMoreSheet(context,
              onOpenZikr: onOpenZikr, onOpenQibla: onOpenQibla),
        ),
        _BarButton(
          icon: Icons.menu_book_rounded,
          label: t('Коран'),
          accent: true,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const QuranPage())),
        ),
      ],
    );
  }

}

/// Лист «Ещё» — все разделы приложения. Вынесен из нижней панели наружу:
/// панель — это три кнопки, а список разделов живёт своей жизнью и его надо
/// уметь открыть со стороны (например, отладочным хуком).
void showMoreSheet(
  BuildContext context, {
  required VoidCallback onOpenZikr,
  required VoidCallback onOpenQibla,
}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      // Высота — по содержимому, а не по доле экрана: раньше лист занимал
      // фиксированные 70% и под последним пунктом оставалась пустая полоса.
      // `shrinkWrap` в рамке 88% высоты: пока пункты влезают, лист ровно по
      // ним, а на коротком экране упирается в потолок и начинает
      // прокручиваться. `isScrollControlled` нужен и здесь — без него потолок
      // листа 9/16 экрана, ниже нашего.
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.88),
        child: GlassSheet(
          opacity: 0.82,
          material: true,
          child: SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
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
                  // Замок ставится здесь, а не внутри каждого экрана: так
                  // видно одним взглядом, что открыто без аккаунта, а что нет.
                  // Под замком только то, что без учётной записи не имеет
                  // смысла (разбор — в AccountGate): всё, что работает на
                  // самом телефоне, открыто и без регистрации.
                  _MenuTile(
                    icon: Icons.menu_book_outlined,
                    title: 'Азкары и дуа',
                    subtitle: 'Утро/вечер, после намаза, поминания',
                    sheet: ctx,
                    free: true,
                    open: (c) => Navigator.push(c,
                        MaterialPageRoute(builder: (_) => const AzkarScreen())),
                  ),
                  _MenuTile(
                    icon: Icons.nightlight_round,
                    title: 'Рамадан',
                    subtitle: 'Сухур, ифтар и дни поста',
                    sheet: ctx,
                    free: true,
                    open: (c) => Navigator.push(c,
                        MaterialPageRoute(
                            builder: (_) => const RamadanScreen())),
                  ),
                  _MenuTile(
                    icon: Icons.sensors,
                    iconColor: Colors.red.shade400,
                    title: 'Прямой эфир',
                    subtitle: 'Трансляции устаза',
                    sheet: ctx,
                    free: true,
                    open: (c) => Navigator.push(c,
                        MaterialPageRoute(builder: (_) => const LiveScreen())),
                  ),
                  _MenuTile(
                    icon: Icons.campaign_outlined,
                    title: 'Новости',
                    subtitle: 'Объявления от устаза',
                    sheet: ctx,
                    free: true,
                    open: (c) => Navigator.push(c,
                        MaterialPageRoute(builder: (_) => const NewsScreen())),
                  ),
                  // Только когда в каталоге есть книги — см. BooksService.hasBooks.
                  if (BooksService.instance.hasBooks)
                    _MenuTile(
                      icon: Icons.local_library_outlined,
                      title: 'Книги',
                      subtitle: 'Библиотека для чтения',
                      sheet: ctx,
                      free: true,
                      open: (c) => Navigator.push(c,
                          MaterialPageRoute(
                              builder: (_) => const BooksScreen())),
                    ),
                  _MenuTile(
                    icon: Icons.explore_outlined,
                    title: 'Кибла',
                    subtitle: 'Компас направления на Мекку',
                    sheet: ctx,
                    free: true,
                    open: (_) => onOpenQibla(),
                  ),
                  _MenuTile(
                    icon: Icons.track_changes,
                    title: 'Счётчик зикров',
                    subtitle: 'Тасбих и дневные цели',
                    sheet: ctx,
                    free: true,
                    open: (_) => onOpenZikr(),
                  ),
                  _MenuTile(
                    icon: Icons.school_outlined,
                    title: 'Курсы',
                    subtitle: 'Обучение основам религии',
                    sheet: ctx,
                    open: (c) => Navigator.push(c,
                        MaterialPageRoute(builder: (_) => const CoursesPage())),
                  ),
                  _MenuTile(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Мои сертификаты',
                    subtitle: 'Дипломы за пройденные модули',
                    sheet: ctx,
                    badge: CertificateService.instance.unseen,
                    open: (c) => Navigator.push(c,
                        MaterialPageRoute(
                            builder: (_) => const CertificatesScreen())),
                  ),
                  _MenuTile(
                    icon: Icons.auto_awesome,
                    title: '99 имён Аллаха',
                    subtitle: 'аль-Асма аль-Хусна',
                    sheet: ctx,
                    free: true,
                    open: (c) => Navigator.push(c,
                        MaterialPageRoute(builder: (_) => const NamesScreen())),
                  ),
                  _MenuTile(
                    icon: Icons.settings_outlined,
                    title: 'Настройки',
                    subtitle: 'Локация, мазхаб, зикры',
                    sheet: ctx,
                    free: true,
                    // Ответы поддержки живут в настройках — туда и ведёт
                    // счётчик, пока пушей об ответе нет.
                    badge: SupportChatService.unreadCount.value,
                    open: (c) => Navigator.push(c,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen())),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
        ),
      ),
    );
}

