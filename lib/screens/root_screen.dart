import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../services/account_backup.dart';
import '../services/api_config.dart';
import '../services/asmaul_husna.dart';
import '../services/certificate_service.dart';
import '../services/quran_audio_cache.dart';
import '../services/quran_service.dart';
import '../services/quran_translations.dart';
import '../services/reciters.dart';
import '../services/verify_service.dart';
import '../services/visual_effects.dart';
import '../services/voice_service.dart';
import '../widgets/account_gate.dart';
import '../widgets/dome_background.dart';
import 'home_page.dart';
import 'names_screen.dart';
import 'news_screen.dart';
import 'account_screen.dart';
import 'azkar_screen.dart';
import 'certificates_screen.dart';
import 'courses_page.dart';
import '../services/staff_auth.dart';
import 'staff/staff_home.dart';
import 'qibla_page.dart';
import 'ramadan_screen.dart';
import 'restore_account_screen.dart';
import 'settings_screen.dart';
import 'tafsir_sheet.dart';
import 'surah_screen.dart';
import 'tracker_page.dart';
import 'zikr_page.dart';
import 'zikr_settings_sheet.dart';

/// Корневой экран: свайпы листают Кибла ← Трекер ← Главная → Зикры → Новости
/// с эффектом перелистывания страницы книги. Коран — по кнопке.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final _controller = PageController(initialPage: 2);

  @override
  void initState() {
    super.initState();
    if (kDebugMode) _applyDebugScreen();
  }

  /// Тестовый хук (только debug-сборка): открывает экран сразу при запуске,
  /// `_speak`-варианты дополнительно включают озвучку — для headless-проверок
  /// на симуляторе без кликов по UI. Флаг — одноразовый файл в Documents
  /// контейнера (значения: names | names_speak | zikr | zikr_speak |
  /// restore:<номер> | restore:<номер>:<код>):
  /// `echo names_speak > "$(xcrun simctl get_app_container booted \
  ///  kg.irfan.irfan data)/Documents/irfan_screen.txt"` перед запуском.
  Future<void> _applyDebugScreen() async {
    String? target;
    final docs = await getApplicationDocumentsDirectory();
    final flag = File('${docs.path}/irfan_screen.txt');
    if (await flag.exists()) {
      target = (await flag.readAsString()).trim();
      await flag.delete();
    }
    debugPrint('IRFAN_SCREEN hook: target=$target');
    if (target == null) return;
    // Формат: "<screen>" или "<screen>:<reciterId>" (для quran_speak).
    final parts = target.split(':');
    final screen = parts.first;
    final reciterArg = parts.length > 1 ? parts[1] : null;
    void attempt() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_controller.hasClients) {
          attempt(); // состояние ещё грузится — PageView не построен
          return;
        }
        if (screen == 'settings') {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()));
        } else if (screen == 'tracker') {
          _controller.jumpToPage(1);
        } else if (screen == 'ramadan') {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const RamadanScreen()));
        } else if (screen == 'azkar') {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AzkarScreen()));
        } else if (screen == 'zikr_settings') {
          _controller.jumpToPage(3);
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) showZikrSettings(context);
          });
        } else if (screen.startsWith('zikr')) {
          _controller.jumpToPage(3);
          if (screen == 'zikr_speak') {
            final goal = AppScope.of(context).zikrs!.goals.first;
            Future.delayed(const Duration(milliseconds: 600), () {
              VoiceService.instance
                  .speak('zikr_${goal.id}', 'audio/zikr/${goal.id}.mp3');
            });
          }
        } else if (screen == 'quran_reset') {
          final qs = AppScope.of(context).quran!;
          qs.setMode(ReadingMode.page);
          qs.setTranslation(translationById('azan'));
          qs.setReciter(reciterById('alafasy'));
        } else if (screen == 'certs') {
          // `certs` — список, `certs:<номер по порядку>` — сразу бланк во весь
          // экран: тапнуть по карточке в симуляторе нечем.
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CertificatesScreen()));
          final i = int.tryParse(reciterArg ?? '');
          final list = CertificateService.instance.items;
          if (i != null && i >= 0 && i < list.length) {
            final female =
                AppScope.of(context).auth?.current?.gender.name == 'female';
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CertificateViewer(
                        cert: list[i],
                        female: female,
                        autoShare: parts.length > 2 && parts[2] == 'share')));
          }
        } else if (screen == 'effects') {
          // `effects:full|light` — уровень оформления. По умолчанию он разный
          // на разных платформах, а сравнивать оба вида надо на одном экране.
          VisualEffects.instance.setLevel(reciterArg == 'light'
              ? EffectsLevel.light
              : EffectsLevel.full);
        } else if (screen == 'account') {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AccountScreen()));
        } else if (screen == 'courses') {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CoursesPage()));
        } else if (screen == 'staff') {
          // `staff` или `staff:<номер вкладки>`.
          StaffHome.open(context,
              initialTab: int.tryParse(reciterArg ?? '') ?? 0);
        } else if (screen == 'staff_login') {
          // `staff_login:<логин>:<пароль>` — вход в кабинет без клавиатуры:
          // в симуляторе печатать нечем, а проверить надо весь путь
          // (сеть → токен → Keychain → вкладки).
          StaffAuth.instance
              .login(reciterArg ?? '', parts.length > 2 ? parts[2] : '')
              .then((err) {
            debugPrint('STAFF_LOGIN result=${err ?? 'ok'} '
                'session=${StaffAuth.instance.session?.login}');
            if (err == null && mounted) StaffHome.open(context);
          });
        } else if (screen == 'restore') {
          // `restore:<номер>` — открыть перенос аккаунта с подставленным
          // номером; `restore:<номер>:<код>` — пройти весь путь целиком.
          // Причина та же, что у staff_login: в симуляторе печатать нечем, а
          // проверять надо не картинку, а цепочку код → разрешение → слепок →
          // пересчёт серии и коинов.
          final phone = reciterArg ?? '';
          if (parts.length > 2) {
            _debugRestore(phone, parts[2]);
          } else {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => RestoreAccountScreen(phone: phone)));
          }
        } else if (screen == 'more') {
          // Лист «Ещё» со всеми разделами: на нём видно, что закрыто замком
          // без аккаунта, а тапнуть по кнопке в симуляторе нечем.
          showMoreSheet(context,
              onOpenZikr: () => _goTo(3), onOpenQibla: () => _goTo(0));
        } else if (screen == 'invite') {
          // `invite:<раздел>` — показать приглашение зарегистрироваться:
          // кнопку на закрытой странице в симуляторе нажать нечем.
          AccountGate.invite(context, reciterArg ?? 'Курсы');
        } else if (screen == 'tafsir') {
          // `tafsir:<сура>:<аят>` — открыть толкование сразу: тапнуть по
          // кнопке на карточке аята в симуляторе нечем.
          showTafsir(context, int.tryParse(reciterArg ?? '') ?? 2,
              int.tryParse(parts.length > 2 ? parts[2] : '') ?? 255);
        } else if (screen == 'quran_dl') {
          // Проверка оффлайн-загрузки: качаем аль-Фатиху и печатаем итог.
          final qs = AppScope.of(context).quran!;
          final cache = QuranAudioCache.instance;
          cache.downloadSurah(qs.reciter, 1).then((ok) async {
            final done = await cache.isSurahDownloaded(qs.reciter, 1);
            final size = await cache.totalSize();
            debugPrint('QURAN_DL result=$ok downloaded=$done '
                'bytes=$size (${formatBytes(size)})');
          });
        } else if (screen.startsWith('quran')) {
          final qs = AppScope.of(context).quran!;
          if (screen == 'quran_speak' && reciterArg != null) {
            qs.setReciter(reciterById(reciterArg));
          }
          if (screen == 'quran_tr' && reciterArg != null) {
            qs.setMode(ReadingMode.sura);
            qs.setTranslation(translationById(reciterArg));
          }
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SurahScreen(
                      surah: 1,
                      autoPlay: screen == 'quran_speak',
                      autoOpenSettings: screen == 'quran_settings')));
        } else if (screen.startsWith('names')) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const NamesScreen()));
          if (screen == 'names_speak') {
            Future.delayed(const Duration(milliseconds: 600), () {
              final name = asmaulHusna.first;
              VoiceService.instance
                  .speak('name_0', 'audio/names/${name.number}.mp3');
            });
          }
        }
      });
    }

    attempt();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) => _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );

  Widget _flipPage(int index, Widget child) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        double page = 2;
        if (_controller.hasClients && _controller.position.haveDimensions) {
          page = _controller.page ?? 2;
        }
        final delta = (index - page).clamp(-1.0, 1.0);
        if (delta == 0) return child;
        // Поворот вокруг ближнего к центру края — как страница книги.
        final angle = delta * -math.pi / 2.5;
        return Transform(
          alignment:
              delta > 0 ? Alignment.centerLeft : Alignment.centerRight,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          child: Opacity(
            opacity: (1 - delta.abs() * 0.4).clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
    );
  }

  /// Отладочный путь переноса аккаунта целиком: подтвердить код, забрать
  /// слепок, применить его и напечатать, что получилось. Только debug.
  Future<void> _debugRestore(String phone, String code) async {
    final state = AppScope.of(context);   // до первого await
    debugPrint('RESTORE base=${await ApiConfig.base()}');
    final v = await VerifyService.confirm(phone, code);
    debugPrint('RESTORE verify=${v.status.name} ticket=${v.ticket.length}');
    if (!v.isOk) return;
    final r = await AccountRestore.fetch(phone, ticket: v.ticket);
    debugPrint('RESTORE fetch=${r.status.name} name=${r.name} '
        'spent=${r.spent} hasData=${r.hasData}');
    if (!r.isOk) return;
    final err = await state.restoreAccount(r,
        phone: phone, password: 'restore123');
    debugPrint('RESTORE apply=${err ?? 'ok'} '
        'streak=${state.tracker?.currentStreak()} '
        'prayers=${state.tracker?.totalReadCount()} coins=${state.coins}');
    if (!mounted) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AccountScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.ready) {
      return const Scaffold(
        body: DomeBackground(
          child: Center(
              child: CircularProgressIndicator(
                  color: Color(0xFFE0C071))),
        ),
      );
    }

    // Без аккаунта закрыт только трекер: его отметки — это запись ученика,
    // она уходит устазу и переезжает между телефонами вместе с аккаунтом.
    // Остальные страницы считаются на самом телефоне и открыты всем.
    // Страница со своего места не убирается — иначе поехали бы индексы всего
    // PageView и переходы `_goTo`; вместо содержимого показываем замок.
    final open = AccountGate.isOpen(context);
    return Scaffold(
      body: DomeBackground(
        child: PageView(
          controller: _controller,
          children: [
            _flipPage(0, const QiblaPage()),
            _flipPage(
                1,
                open
                    ? const TrackerPage()
                    : const LockedPage(
                        icon: Icons.track_changes,
                        title: 'Трекер намазов',
                        subtitle: 'Отметки намазов, серия дней и статистика '
                            'хранятся в вашем аккаунте.')),
            _flipPage(
              2,
              HomePage(
                onOpenTracker: () => _goTo(1),
                onOpenZikr: () => _goTo(3),
                onOpenQibla: () => _goTo(0),
              ),
            ),
            _flipPage(3, const ZikrPage()),
            _flipPage(4, const NewsPage()),
          ],
        ),
      ),
    );
  }
}
