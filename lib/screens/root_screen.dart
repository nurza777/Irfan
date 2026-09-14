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
import '../services/lang.dart';
import '../services/notification_service.dart';
import '../services/prayer_service.dart';
import '../services/quran_audio_cache.dart';
import '../services/quran_service.dart';
import '../services/quran_translations.dart';
import '../services/reciters.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart' show AuthService;
import '../services/visual_effects.dart';
import '../services/voice_service.dart';
import '../widgets/account_gate.dart';
import '../widgets/city_picker.dart';
import '../widgets/dome_background.dart';
import 'home_page.dart';
import 'names_screen.dart';
import 'news_screen.dart';
import 'account_screen.dart';
import 'azkar_screen.dart';
import 'book_reader_screen.dart';
import 'books_screen.dart';
import '../services/books_service.dart';
import 'certificates_screen.dart';
import 'courses_page.dart';
import '../services/staff_auth.dart';
import 'staff/staff_home.dart';
import 'qibla_page.dart';
import 'quran_page.dart';
import 'rating_screen.dart';
import 'ramadan_screen.dart';
import 'restore_account_screen.dart';
import 'settings_screen.dart';
import 'support_chat_screen.dart';
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
    // Человек нажал по уведомлению «прочитали ли вы намаз», а не по кнопке
    // в нём: спросим то же самое окном. Подписка и разбор повода запуска —
    // два разных случая (приложение работало / было выгружено), нужны оба.
    NotificationService.pendingAsk.addListener(_onPendingAsk);
    NotificationService.consumeLaunchPayload();
    _onPendingAsk();
  }

  /// Показывает вопрос окном. Значение забираем сразу, чтобы повторный показ
  /// не случился ни при пересборке, ни при возврате из фона.
  void _onPendingAsk() {
    final payload = NotificationService.pendingAsk.value;
    if (payload == null) return;
    NotificationService.pendingAsk.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _askDialog(payload);
    });
  }

  Future<void> _askDialog(String payload) async {
    final parts = payload.split('|');
    if (parts.length != 3) return;
    final key = PrayerKey.values.where((k) => k.name == parts[2]).firstOrNull;
    if (key == null) return;
    final name = t(key.titleRu);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appLang == Lang.ky
            ? '$name намазын окудуңузбу?'
            : 'Прочитали ли вы намаз $name?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(t('Нет'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(t('Да'))),
        ],
      ),
    );
    if (yes == null) return;   // окно закрыли, не ответив
    await NotificationService.answerAsk(payload, yes);
    if (mounted) _goTo(1);     // показываем трекер с новой отметкой
  }

  /// Тестовый хук (только debug-сборка): открывает экран сразу при запуске,
  /// `_speak`-варианты дополнительно включают озвучку — для headless-проверок
  /// на симуляторе без кликов по UI. Флаг — одноразовый файл в Documents
  /// контейнера (значения: names | names_speak | zikr | zikr_speak |
  /// restore:<номер> | restore:<номер>:<пароль>):
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
        } else if (screen == 'rating') {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const RatingScreen()));
        } else if (screen == 'support_chat') {
          // Экран переписки с поддержкой: до него иначе три нажатия вглубь
          // настроек, а проверять его надо в состоянии «аккаунта нет» —
          // то есть на чистой установке, где нажимать нечем.
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SupportChatScreen()));
        } else if (screen == 'books') {
          // `books` — список, `books:<номер по порядку>` — скачать книгу и
          // сразу открыть её: в симуляторе без нажатий иначе не проверить
          // ни загрузку, ни сам просмотрщик PDF.
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const BooksScreen()));
          final i = int.tryParse(reciterArg ?? '');
          if (i != null) {
            final svc = BooksService.instance;
            svc.fetch().then((list) async {
              if (list == null || i < 0 || i >= list.length) return;
              final ok = await svc.download(list[i]);
              debugPrint('BOOK_HOOK download=$ok id=${list[i].id}');
              if (ok && mounted) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => BookReaderScreen(book: list[i])));
              }
            });
          }
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
                AppScope.of(context).auth?.current?.gender?.name == 'female';
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
        } else if (screen == 'ask_demo') {
          // `ask_demo` — показать вопрос «прочитали ли вы намаз» через 5 с.
          // Ждать настоящего времени намаза для проверки кнопок нельзя,
          // а сами кнопки живут в системном слое и тестами не покрываются.
          NotificationService.showAskDemo(
              AppScope.of(context).settings!, PrayerKey.fajr);
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
          // номером; `restore:<номер>:<пароль>` — пройти весь путь целиком.
          // Причина та же, что у staff_login: в симуляторе печатать нечем, а
          // проверять надо не картинку, а цепочку пароль → слепок → пересчёт
          // серии и коинов.
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
        } else if (screen == 'city') {
          // `city` — открыть выбор города, `city:<название>` — сразу спросить
          // геокодер и применить найденное. Второй вид нужен потому, что в
          // симуляторе нечем ни печатать, ни попасть по строке поиска:
          // всплывашка автозамены перекрывает её.
          if (reciterArg != null && reciterArg.isNotEmpty) {
            SettingsService.findCity(reciterArg).then((c) {
              debugPrint('CITY found=${c?.name} ${c?.lat},${c?.lon}');
              if (c != null && mounted) {
                AppScope.of(context).setManualCity(c);
              }
            });
            return;
          }
          showCityPicker(context).then((c) {
            debugPrint('CITY picked=${c?.name} ${c?.lat},${c?.lon}');
            if (c != null && mounted) AppScope.of(context).setManualCity(c);
          });
        } else if (screen == 'quran_list') {
          // Список сур: с него начинается раздел, а кнопку «КОРАН» на
          // главной в симуляторе нажать нечем.
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const QuranPage()));
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
    NotificationService.pendingAsk.removeListener(_onPendingAsk);
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) => _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );

  Widget _flipPage(int index, Widget page) {
    return AnimatedBuilder(
      animation: _controller,
      // Страницу передаём отдельным доводом, а не замыканием: так она
      // строится один раз, а на каждый пиксель прокрутки пересобирается
      // только обёртка с поворотом.
      child: page,
      builder: (context, child) {
        double pos = 2;
        if (_controller.hasClients && _controller.position.haveDimensions) {
          pos = _controller.page ?? 2;
        }
        final delta = (index - pos).clamp(-1.0, 1.0);
        // Обёртка ставится ВСЕГДА, даже когда поворачивать нечего.
        //
        // Раньше у страницы по центру возвращался голый child, а у соседних —
        // Transform поверх него. Дерево виджетов от этого меняло форму на
        // каждом заезде страницы в центр, Flutter считал это другим виджетом
        // и пересоздавал всё поддерево вместе с его состоянием: каскад
        // появления блоков проигрывался заново при каждом переходе, а экран
        // «обновлялся дважды». Постоянная форма дерева это убирает.
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

  /// Отладочный путь переноса аккаунта целиком: сверить пароль, забрать
  /// слепок, применить его и напечатать, что получилось. Только debug.
  Future<void> _debugRestore(String phone, String password) async {
    final state = AppScope.of(context);   // до первого await
    debugPrint('RESTORE base=${await ApiConfig.base()}');
    final proof = await AuthService.makeProof(phone, password);
    final r = await AccountRestore.fetch(phone, pass: proof);
    debugPrint('RESTORE fetch=${r.status.name} name=${r.name} '
        'spent=${r.spent} hasData=${r.hasData}');
    if (!r.isOk) return;
    final err = await state.restoreAccount(r,
        phone: phone, password: password);
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
