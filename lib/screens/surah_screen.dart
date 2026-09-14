import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;

import '../app_state.dart';
import '../services/quran_audio_cache.dart';
import '../services/reciters.dart';
import '../services/quran_service.dart';
import '../services/tajwid.dart';
import '../services/lang.dart';
import '../services/surah_names.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import 'quran_settings_sheet.dart';
import 'tafsir_sheet.dart';
import 'tajwid_sheet.dart';

/// Чтение суры: арабский текст с подсветкой таджвида, перевод Azan.ru,
/// закладки, заметки и аудио (Мишари Рашид аль-Афаси): тап по аяту или
/// кнопка в шапке — непрерывное чтение до конца суры. Режим — из настроек.
class SurahScreen extends StatefulWidget {
  final int surah;
  final int? scrollToVerse;
  final bool autoPlay;
  final bool autoOpenSettings;
  const SurahScreen(
      {super.key,
      required this.surah,
      this.scrollToVerse,
      this.autoPlay = false,
      this.autoOpenSettings = false});

  @override
  State<SurahScreen> createState() => _SurahScreenState();
}

class _SurahScreenState extends State<SurahScreen> {
  final _player = AudioPlayer();
  int? _playingVerse;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) => _onVerseFinished());
    // Подгружаем выбранный перевод (если он из ассета и ещё не в кэше).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final qs = AppScope.of(context).quran!;
      qs.ensureTranslationLoaded(qs.translation);
    });
    if (widget.autoPlay) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _playVerse(widget.scrollToVerse ?? 1));
    }
    if (widget.autoOpenSettings) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => showQuranSettings(context));
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// Аят дочитан — переходим к следующему до конца суры.
  void _onVerseFinished() {
    if (!mounted) return;
    final v = _playingVerse;
    if (v != null && v < quran.getVerseCount(widget.surah)) {
      _playVerse(v + 1);
    } else {
      setState(() => _playingVerse = null);
    }
  }

  Future<void> _playVerse(int verse) async {
    if (!mounted) return;
    final reciter = AppScope.of(context).quran!.reciter;
    setState(() => _playingVerse = verse);
    // Скачанный файл — приоритетнее стрима: работает без сети и не тратит
    // трафик. Если аята нет локально, играем с CDN как раньше.
    final local =
        await QuranAudioCache.instance.localVerse(reciter, widget.surah, verse);
    await _player.stop();
    if (local != null) {
      await _player.play(DeviceFileSource(local));
    } else {
      await _player.play(UrlSource(reciter.audioUrl(widget.surah, verse)));
    }
  }

  Future<void> _stop() async {
    await _player.stop();
    if (mounted) setState(() => _playingVerse = null);
  }

  /// Тап по аяту: слушать с него и дальше; повторный тап — стоп.
  Future<void> _toggleAudio(int verse) async {
    if (_playingVerse == verse) return _stop();
    await _playVerse(verse);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final qs = state.quran!;
    final surah = widget.surah;

    return AnimatedBuilder(
      animation: qs,
      builder: (context, _) {
        final mode = qs.mode;
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            centerTitle: true,
            title: Column(
              children: [
                Text(surahName(surah),
                    style: const TextStyle(fontSize: 18)),
                Text(
                  '${quran.getSurahNameArabic(surah)} · '
                  '${t(quran.getPlaceOfRevelation(surah) == "Makkah" ? "Мекканская" : "Мединская")} · '
                  '${verseCountLabel(quran.getVerseCount(surah))}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.goldLight),
                ),
              ],
            ),
            actions: [
              _OfflineButton(reciter: qs.reciter, surah: surah),
              IconButton(
                tooltip: _playingVerse == null
                    ? t('Слушать суру')
                    : t('Остановить чтение'),
                onPressed: () =>
                    _playingVerse == null ? _playVerse(1) : _stop(),
                icon: Icon(
                  _playingVerse == null
                      ? Icons.headphones_outlined
                      : Icons.stop_circle,
                  color: AppColors.goldLight,
                ),
              ),
            ],
          ),
          body: DomeBackground(
            child: mode == ReadingMode.page
                ? _PageMode(
                    surah: surah,
                    qs: qs,
                    scrollToVerse: widget.scrollToVerse,
                    playingVerse: _playingVerse,
                    onToggleAudio: _toggleAudio,
                  )
                : _SuraMode(
                    surah: surah,
                    qs: qs,
                    playingVerse: _playingVerse,
                    onToggleAudio: _toggleAudio,
                    scrollToVerse: widget.scrollToVerse,
                  ),
          ),
          bottomNavigationBar: _BottomTools(
            onTajwid: () => showTajwidLegend(context),
            onSettings: () => showQuranSettings(context),
          ),
        );
      },
    );
  }
}

/// Режим «Сура» — карточки аятов со всеми действиями.
class _SuraMode extends StatelessWidget {
  final int surah;
  final QuranService qs;
  final int? playingVerse;
  final void Function(int verse) onToggleAudio;
  final int? scrollToVerse;
  const _SuraMode({
    required this.surah,
    required this.qs,
    required this.playingVerse,
    required this.onToggleAudio,
    this.scrollToVerse,
  });

  @override
  Widget build(BuildContext context) {
    final display = qs.display;
    final verseCount = quran.getVerseCount(surah);
    final showBasmala = surah != 1 && surah != 9;

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 66, 16, 90),
      itemCount: verseCount + (showBasmala ? 1 : 0),
      itemBuilder: (context, i) {
        if (showBasmala && i == 0) {
          return FadeSlideIn(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 4),
              child: Text(quran.basmala,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      fontFamily: qs.arabicFont.family,
                      fontSize: 26,
                      color: AppColors.goldLight)),
            ),
          );
        }
        final verse = showBasmala ? i : i + 1;
        return _VerseCard(
          surah: surah,
          verse: verse,
          qs: qs,
          display: display,
          playing: playingVerse == verse,
          onToggleAudio: () => onToggleAudio(verse),
        );
      },
    );
  }
}

class _VerseCard extends StatelessWidget {
  final int surah;
  final int verse;
  final QuranService qs;
  final QuranDisplay display;
  final bool playing;
  final VoidCallback onToggleAudio;
  const _VerseCard({
    required this.surah,
    required this.verse,
    required this.qs,
    required this.display,
    required this.playing,
    required this.onToggleAudio,
  });

  @override
  Widget build(BuildContext context) {
    final bookmarked = qs.isBookmarked(surah, verse);
    final note = qs.noteOf(surah, verse);
    final isSajdah = quran.isSajdahVerse(surah, verse);
    final arabicStyle = TextStyle(
        fontFamily: qs.arabicFont.family,
        fontSize: qs.arabicFontSize,
        height: 2.0,
        color: Colors.white);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 16,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.domeGreen.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.5)),
                  ),
                  child: Text('$surah:$verse',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.goldLight)),
                ),
                if (isSajdah) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.self_improvement,
                      size: 16, color: AppColors.goldLight),
                ],
                const Spacer(),
                _VerseAction(
                  icon: playing ? Icons.stop_circle : Icons.play_circle_outline,
                  active: playing,
                  onTap: onToggleAudio,
                ),
                _VerseAction(
                  icon: note != null && note.isNotEmpty
                      ? Icons.sticky_note_2
                      : Icons.note_add_outlined,
                  active: note != null && note.isNotEmpty,
                  onTap: () => _editNote(context),
                ),
                _VerseAction(
                  icon: Icons.menu_book_outlined,
                  active: false,
                  onTap: () => showTafsir(context, surah, verse),
                ),
                _VerseAction(
                  icon: bookmarked
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  active: bookmarked,
                  onTap: () => qs.toggleBookmark(surah, verse),
                ),
              ],
            ),
            if (display.arabic) ...[
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  children: [
                    if (display.tajwid)
                      ...Tajwid.spans(
                          quran.getVerse(surah, verse), arabicStyle)
                    else
                      TextSpan(
                          text: quran.getVerse(surah, verse),
                          style: arabicStyle),
                    TextSpan(
                        text: ' ${quran.getVerseEndSymbol(verse)}',
                        style: arabicStyle.copyWith(
                            color: AppColors.goldLight)),
                  ],
                ),
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
              ),
            ],
            if (display.translation) ...[
              const SizedBox(height: 12),
              Builder(builder: (_) {
                final text = qs.translationOf(surah, verse);
                if (text.isEmpty && !qs.translationReady) {
                  return Text(t('Загрузка перевода…'),
                      style: TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: Colors.white.withValues(alpha: 0.5)));
                }
                return Text(
                  text,
                  style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Colors.white.withValues(alpha: 0.85)),
                );
              }),
            ],
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                      left: BorderSide(color: AppColors.gold, width: 3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.edit_note,
                        size: 18, color: AppColors.goldLight),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(note,
                          style: const TextStyle(
                              fontSize: 14, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editNote(BuildContext context) =>
      showQuranNoteEditor(context, qs, surah, verse);
}

/// Редактор заметки к аяту (общий для режимов «Сура» и «Страница»).
Future<void> showQuranNoteEditor(
    BuildContext context, QuranService qs, int surah, int verse) async {
  final ctrl = TextEditingController(text: qs.noteOf(surah, verse) ?? '');
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.skyBottom,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${t('Заметка к аяту')} $surah:$verse',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 4,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: t('Ваши мысли, тафсир, напоминание…'),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.3),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentGreen),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(t('Сохранить')),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.4))),
                onPressed: () {
                  ctrl.clear();
                  Navigator.pop(ctx, true);
                },
                child: Text(t('Удалить')),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  final note = ctrl.text;
  ctrl.dispose();
  if (saved == true) await qs.setNote(surah, verse, note);
}

class _VerseAction extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _VerseAction(
      {required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(icon,
          size: 22,
          color: active
              ? AppColors.goldLight
              : Colors.white.withValues(alpha: 0.6)),
    );
  }
}

/// Режим «Страница» — постранично, как в мусхафе, в стиле старой книги:
/// сепия-бумага, чернильный текст, закладка и заметка к текущей странице.
class _PageMode extends StatefulWidget {
  final int surah;
  final QuranService qs;
  final int? scrollToVerse;
  final int? playingVerse;
  final void Function(int verse) onToggleAudio;
  const _PageMode({
    required this.surah,
    required this.qs,
    this.scrollToVerse,
    required this.playingVerse,
    required this.onToggleAudio,
  });

  @override
  State<_PageMode> createState() => _PageModeState();
}

class _PageModeState extends State<_PageMode> {
  late final List<int> _pages = quran.getSurahPages(widget.surah);
  late final PageController _controller;
  late int _index;

  /// Чтобы переход к следующей суре не сработал дважды: `onPageChanged`
  /// зовётся и при мелких доводках положения страницы.
  bool _leaving = false;

  /// Страницу листает не человек, а само приложение — вслед за чтением.
  bool _programmatic = false;

  /// Распознаватели тапа по аятам — по одному на аят, живут с экраном.
  /// Создавать их в каждой перерисовке нельзя: распознаватель надо
  /// освобождать, а спаны о своих не заботятся.
  final Map<int, TapGestureRecognizer> _taps = {};

  /// Есть ли следующая сура. У 114-й её нет, и лишней страницы «дальше»
  /// в конце не будет — листание просто упирается в последнюю страницу.
  bool get _hasNext => widget.surah < quran.totalSurahCount;

  /// Переход к следующей суре — со страницы-перехода после последней.
  ///
  /// Раньше переход срабатывал, стоило ДОЙТИ до последней страницы: на её
  /// чтение оставалось полсекунды, а у сур в одну страницу перехода не было
  /// вовсе (страница не менялась — нечему было сработать). Теперь последняя
  /// страница читается спокойно, а переход — отдельный свайп за неё.
  ///
  /// Пауза нужна, чтобы человек увидел, куда долистал, и успел вернуться.
  /// Экран ЗАМЕНЯЕМ, а не кладём поверх: иначе «назад» уводило бы через всю
  /// прочитанную цепочку сур обратно к самой первой.
  void _goNextSurah() {
    if (_leaving || !_hasNext) return;
    final next = widget.surah + 1;
    _leaving = true;
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      // За паузу успели свайпнуть обратно — остаёмся в этой суре.
      if (_controller.hasClients &&
          (_controller.page ?? 0).round() != _pages.length) {
        _leaving = false;
        return;
      }
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => SurahScreen(surah: next)));
    });
  }

  TapGestureRecognizer _tapFor(int verse) =>
      _taps.putIfAbsent(verse, () => TapGestureRecognizer())
        ..onTap = () => _showVerse(verse);

  /// Тап по аяту на странице: перевод именно этого аята и действия с ним.
  ///
  /// Перевод под страницей есть и так (по переключателю в настройках), но
  /// там он — сплошным блоком после всей вязи, и найти нужный аят в нём
  /// приходится по номеру. Тап отвечает на вопрос «а что значит вот это»
  /// прямо там, где человек читает, — и работает, даже когда перевод под
  /// страницей выключен, чтобы лист оставался чистым.
  void _showVerse(int verse) {
    final qs = widget.qs;
    qs.ensureTranslationLoaded(qs.translation);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VerseSheet(
        surah: widget.surah,
        verse: verse,
        qs: qs,
        onListen: () {
          Navigator.pop(ctx);
          widget.onToggleAudio(verse);
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _index = widget.scrollToVerse != null
        ? _pageIndexForVerse(widget.scrollToVerse!)
        : 0;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final r in _taps.values) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PageMode old) {
    super.didUpdateWidget(old);
    // Чтение перешло на аят с другой страницы — перелистываем за ним.
    final pv = widget.playingVerse;
    if (pv != null && pv != old.playingVerse) {
      final target = _pageIndexForVerse(pv);
      if (target != _index && _controller.hasClients) {
        // Отмечаем, что листаем сами. Иначе последняя страница суры,
        // до которой добралось чтение вслух, уводила бы человека в
        // следующую суру прямо посреди прослушивания.
        _programmatic = true;
        _controller
            .animateToPage(target,
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeInOutCubic)
            .whenComplete(() => _programmatic = false);
      }
    }
  }

  /// Индекс страницы (в пределах суры), где находится [verse].
  int _pageIndexForVerse(int verse) {
    for (int i = 0; i < _pages.length; i++) {
      for (final data in quran.getPageData(_pages[i])) {
        if (data['surah'] == widget.surah &&
            verse >= (data['start'] as int) &&
            verse <= (data['end'] as int)) {
          return i;
        }
      }
    }
    return 0;
  }

  /// Первый аят текущей суры на странице — «якорь» для закладки/заметки.
  int? _anchorVerse(int page) {
    int? first;
    for (final data in quran.getPageData(page)) {
      if (data['surah'] != widget.surah) continue;
      final start = data['start'] as int;
      if (first == null || start < first) first = start;
    }
    return first;
  }

  @override
  Widget build(BuildContext context) {
    final qs = widget.qs;
    final display = qs.display;
    final arabicStyle = TextStyle(
        fontFamily: qs.arabicFont.family,
        fontSize: qs.arabicFontSize + 2,
        height: 2.35,
        color: AppColors.ink,
        fontWeight: FontWeight.w500);

    final page = _pages[_index];
    final anchor = _anchorVerse(page);
    final bookmarked = anchor != null && qs.isBookmarked(widget.surah, anchor);
    final note = anchor != null ? qs.noteOf(widget.surah, anchor) : null;
    final hasNote = note != null && note.isNotEmpty;

    return Column(
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top + 60),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            // Листаем справа налево, как настоящий мусхаф: следующая
            // страница приходит слева. Порядок самих страниц при этом не
            // меняется — переворачивается только жест.
            reverse: true,
            // Лишний лист в конце — переход к следующей суре (см. _goNextSurah).
            itemCount: _pages.length + (_hasNext ? 1 : 0),
            onPageChanged: (i) {
              if (i >= _pages.length) {
                if (!_programmatic) _goNextSurah();
                return;   // панель внизу остаётся на последней странице
              }
              setState(() => _index = i);
            },
            itemBuilder: (context, i) {
              if (i >= _pages.length) {
                return _NextSurahPage(next: widget.surah + 1);
              }
              final p = _pages[i];
              final pNote = _anchorVerse(p) != null
                  ? qs.noteOf(widget.surah, _anchorVerse(p)!)
                  : null;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                child: _Parchment(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PageHeading(page: p),
                      const SizedBox(height: 16),
                      Text.rich(
                        TextSpan(
                            children: _pageSpans(
                                p, arabicStyle, display.tajwid)),
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.justify,
                      ),
                      // Перевод под страницей.
                      //
                      // Раньше его тут не было вовсе: страница задумывалась
                      // как лист мусхафа, сплошным арабским. Но человеку,
                      // который не читает по-арабски, такая страница
                      // бесполезна — а переключаться ради перевода в другой
                      // режим значит терять место в чтении.
                      //
                      // Порядок «сначала весь арабский, потом переводы по
                      // аятам» взят у печатных изданий с подстрочником:
                      // лист остаётся цельным, перевод не разрывает вязь.
                      // Показывается по тому же переключателю, что и в
                      // режиме суры, — выключается там же.
                      if (display.translation) ..._pageTranslation(p, qs),
                      if (pNote != null && pNote.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _MarginNote(text: pNote),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _PageBar(
          index: _index,
          total: _pages.length,
          bookmarked: bookmarked,
          hasNote: hasNote,
          playing: widget.playingVerse != null,
          onListen: anchor == null
              ? null
              : () => widget
                  .onToggleAudio(widget.playingVerse ?? anchor),
          onBookmark: anchor == null
              ? null
              : () => qs.toggleBookmark(widget.surah, anchor),
          onNote: anchor == null
              ? null
              : () =>
                  showQuranNoteEditor(context, qs, widget.surah, anchor),
        ),
      ],
    );
  }

  /// Спаны страницы поаятно (только аяты текущей суры); звучащий сейчас
  /// аят подсвечивается золотым фоном.
  /// Номера аятов текущей суры, попавших на эту страницу.
  List<int> _pageVerses(int page) {
    final out = <int>[];
    for (final data in quran.getPageData(page)) {
      if (data['surah'] != widget.surah) continue;
      for (int v = data['start']; v <= data['end']; v++) {
        out.add(v);
      }
    }
    return out;
  }

  /// Блок перевода под страницей: номер аята и его перевод.
  List<Widget> _pageTranslation(int page, QuranService qs) {
    final verses = _pageVerses(page);
    if (verses.isEmpty) return const [];
    // Цвета — чернила по бумаге, как у самой вязи. Раньше перевод был
    // белым, как на тёмных карточках режима суры, и на светлом листе
    // мусхафа его почти не было видно.
    if (!qs.translationReady) {
      return [
        const SizedBox(height: 18),
        Text(t('Загрузка перевода…'),
            style: const TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: AppColors.inkSoft)),
      ];
    }
    return [
      const SizedBox(height: 18),
      Divider(
          color: AppColors.paperEdge.withValues(alpha: 0.6), height: 1),
      const SizedBox(height: 14),
      for (final v in verses) ...[
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '$v. ',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.paperEdge)),
            TextSpan(text: qs.translationOf(widget.surah, v)),
          ]),
          style: const TextStyle(
              fontSize: 15, height: 1.5, color: AppColors.ink),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<TextSpan> _pageSpans(int page, TextStyle base, bool tajwid) {
    final spans = <TextSpan>[];
    for (final data in quran.getPageData(page)) {
      if (data['surah'] != widget.surah) continue;
      for (int v = data['start']; v <= data['end']; v++) {
        final style = v == widget.playingVerse
            ? base.copyWith(
                backgroundColor: AppColors.gold.withValues(alpha: 0.3))
            : base;
        final text = quran.getVerse(widget.surah, v);
        // Распознаватель ставится на каждый кусок аята: Flutter берёт его
        // у того спана, в который попал палец, а не у родителя.
        final tap = _tapFor(v);
        if (tajwid) {
          for (final s in Tajwid.spans(text, style)) {
            spans.add(TextSpan(text: s.text, style: s.style, recognizer: tap));
          }
        } else {
          spans.add(TextSpan(text: text, style: style, recognizer: tap));
        }
        spans.add(TextSpan(
            text: ' ${quran.getVerseEndSymbol(v)} ',
            style: style,
            recognizer: tap));
      }
    }
    return spans;
  }
}

/// Лист после последней страницы суры: куда поведёт следующий свайп.
///
/// Сам по себе он и есть подсказка — человек видит название следующей суры
/// ещё до того, как экран сменится, и может свайпнуть обратно.
class _NextSurahPage extends StatelessWidget {
  final int next;
  const _NextSurahPage({required this.next});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories_outlined,
                size: 40, color: AppColors.goldLight),
            const SizedBox(height: 14),
            Text(t('Следующая сура'),
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textFaint)),
            const SizedBox(height: 6),
            Text('$next. ${surahName(next)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(quran.getSurahNameArabic(next),
                style: const TextStyle(
                    fontSize: 18, color: AppColors.goldLight)),
            const SizedBox(height: 20),
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
    );
  }
}

/// Лист с одним аятом: вязь, перевод и то, что с аятом можно сделать.
class _VerseSheet extends StatelessWidget {
  final int surah;
  final int verse;
  final QuranService qs;
  final VoidCallback onListen;
  const _VerseSheet({
    required this.surah,
    required this.verse,
    required this.qs,
    required this.onListen,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12211F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        // Перевод может догружаться, пока лист открыт, — слушаем сервис,
        // чтобы текст появился сам, а не после повторного тапа.
        child: AnimatedBuilder(
          animation: qs,
          builder: (context, _) {
            final bookmarked = qs.isBookmarked(surah, verse);
            final translation = qs.translationOf(surah, verse);
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text('${surahName(surah)} · $surah:$verse',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.goldLight)),
                const SizedBox(height: 12),
                Text(
                  '${quran.getVerse(surah, verse)} '
                  '${quran.getVerseEndSymbol(verse)}',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      fontFamily: qs.arabicFont.family,
                      fontSize: qs.arabicFontSize,
                      height: 2.0,
                      color: Colors.white),
                ),
                const SizedBox(height: 14),
                if (translation.isNotEmpty)
                  Text(translation,
                      style: const TextStyle(
                          fontSize: 16, height: 1.5, color: AppColors.textSoft))
                else
                  Text(
                      qs.translationReady
                          ? t('Перевода этого аята нет')
                          : t('Загрузка перевода…'),
                      style: const TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textFaint)),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onListen,
                      icon: const Icon(Icons.play_circle_outline),
                      label: Text(t('Слушать с этого аята')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => showTafsir(context, surah, verse),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text(t('Тафсир')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => qs.toggleBookmark(surah, verse),
                      icon: Icon(bookmarked
                          ? Icons.bookmark
                          : Icons.bookmark_border),
                      label: Text(
                          bookmarked ? t('В закладках') : t('В закладки')),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Лист «старой бумаги» с рамкой — фон страницы мусхафа.
class _Parchment extends StatelessWidget {
  final Widget child;
  const _Parchment({required this.child});

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.paper, AppColors.paperDark],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 10)),
          ],
        ),
        padding: const EdgeInsets.all(6),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.paperEdge, width: 1.4),
          ),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: child,
        ),
      ),
    );
  }
}

/// Шапка страницы с орнаментом: «﴿ Страница N ﴾».
class _PageHeading extends StatelessWidget {
  final int page;
  const _PageHeading({required this.page});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('﴿',
                style: TextStyle(fontSize: 18, color: AppColors.paperEdge)),
            const SizedBox(width: 8),
            Text('${t('Страница')} $page',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.inkSoft)),
            const SizedBox(width: 8),
            const Text('﴾',
                style: TextStyle(fontSize: 18, color: AppColors.paperEdge)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
            height: 1.2,
            color: AppColors.paperEdge.withValues(alpha: 0.5)),
      ],
    );
  }
}

/// Заметка на полях страницы — рукописный вид на бумаге.
class _MarginNote extends StatelessWidget {
  final String text;
  const _MarginNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.paperEdge.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
            left: BorderSide(color: AppColors.paperEdge, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.edit_note, size: 18, color: AppColors.inkSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                    color: AppColors.ink)),
          ),
        ],
      ),
    );
  }
}

/// Нижняя панель режима «Страница»: закладка, заметка, счётчик страниц.
class _PageBar extends StatelessWidget {
  final int index;
  final int total;
  final bool bookmarked;
  final bool hasNote;
  final bool playing;
  final VoidCallback? onListen;
  final VoidCallback? onBookmark;
  final VoidCallback? onNote;
  const _PageBar({
    required this.index,
    required this.total,
    required this.bookmarked,
    required this.hasNote,
    required this.playing,
    required this.onListen,
    required this.onBookmark,
    required this.onNote,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: GlassCard(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            _PageBarAction(
              icon: playing
                  ? Icons.stop_circle
                  : Icons.headphones_outlined,
              label: playing ? t('Стоп') : t('Слушать'),
              active: playing,
              onTap: onListen,
            ),
            _PageBarAction(
              icon: bookmarked ? Icons.bookmark : Icons.bookmark_border,
              label: '',
              active: bookmarked,
              onTap: onBookmark,
            ),
            _PageBarAction(
              icon: hasNote ? Icons.sticky_note_2 : Icons.note_add_outlined,
              label: '',
              active: hasNote,
              onTap: onNote,
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text('${index + 1} / $total',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.7))),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageBarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  const _PageBarAction({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? AppColors.goldLight
        : Colors.white.withValues(alpha: 0.72);
    if (label.isEmpty) {
      return IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: color),
      );
    }
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      icon: Icon(icon, size: 20, color: color),
      label: Text(label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: color)),
    );
  }
}

/// Нижняя панель инструментов чтения: правила таджвида и настройки.
/// Заменила две плавающие кнопки, что стояли справа.
class _BottomTools extends StatelessWidget {
  final VoidCallback onTajwid;
  final VoidCallback onSettings;
  const _BottomTools({required this.onTajwid, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: GlassCard(
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: _BottomToolButton(
                  icon: Icons.palette_outlined,
                  label: t('Таджвид'),
                  onTap: onTajwid,
                ),
              ),
              Container(
                width: 1,
                height: 24,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              Expanded(
                child: _BottomToolButton(
                  icon: Icons.tune,
                  label: t('Настройки'),
                  onTap: onSettings,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BottomToolButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.cream,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      icon: Icon(icon, size: 20, color: AppColors.cream),
      label: Text(label,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }
}

/// Кнопка «скачать суру для оффлайна» в шапке читалки: показывает прогресс
/// во время загрузки и галочку, когда сура уже на устройстве.
class _OfflineButton extends StatefulWidget {
  final QuranReciter reciter;
  final int surah;
  const _OfflineButton({required this.reciter, required this.surah});

  @override
  State<_OfflineButton> createState() => _OfflineButtonState();
}

class _OfflineButtonState extends State<_OfflineButton> {
  bool _downloaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    QuranAudioCache.instance.revision.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _OfflineButton old) {
    super.didUpdateWidget(old);
    // Сменили чтеца или суру — статус другой.
    if (old.reciter.id != widget.reciter.id || old.surah != widget.surah) {
      _refresh();
    }
  }

  @override
  void dispose() {
    QuranAudioCache.instance.revision.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final v = await QuranAudioCache.instance
        .isSurahDownloaded(widget.reciter, widget.surah);
    if (mounted) setState(() => _downloaded = v);
  }

  Future<void> _tap(DownloadProgress? progress) async {
    final cache = QuranAudioCache.instance;
    if (progress != null) {
      cache.cancel(widget.reciter, widget.surah);
      return;
    }
    if (_downloaded) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.skyBottom,
          title: Text(t('Удалить загрузку?')),
          content: Text(t('Аудио суры будет удалено с устройства.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t('Отмена'))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t('Удалить'))),
          ],
        ),
      );
      if (yes == true) {
        await cache.deleteSurah(widget.reciter, widget.surah);
      }
      return;
    }
    final ok = await cache.downloadSurah(widget.reciter, widget.surah);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('Загрузка прервана — проверьте интернет'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = QuranAudioCache.keyOf(widget.reciter, widget.surah);
    return ValueListenableBuilder<Map<String, DownloadProgress>>(
      valueListenable: QuranAudioCache.instance.active,
      builder: (context, activeMap, _) {
        final p = activeMap[key];
        return IconButton(
          tooltip: p != null
              ? t('Отменить загрузку')
              : _downloaded
                  ? t('Удалить загрузку')
                  : t('Скачать для оффлайна'),
          onPressed: () => _tap(p),
          icon: p != null
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: p.fraction,
                    strokeWidth: 2.4,
                    valueColor: const AlwaysStoppedAnimation(
                        AppColors.goldLight),
                    backgroundColor: Colors.white24,
                  ),
                )
              : Icon(
                  _downloaded
                      ? Icons.download_done
                      : Icons.download_for_offline_outlined,
                  color: _downloaded
                      ? AppColors.accentGreen
                      : AppColors.goldLight,
                ),
        );
      },
    );
  }
}
