import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;

import '../services/lang.dart';
import '../services/surah_names.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import 'bookmarks_screen.dart';
import 'surah_screen.dart';

/// Список 114 сур — отдельный экран (открывается кнопкой «КОРАН»).
/// Тап по суре — чтение (арабский + перевод Azan.ru).
class QuranPage extends StatefulWidget {
  const QuranPage({super.key});

  @override
  State<QuranPage> createState() => _QuranPageState();
}

class _QuranPageState extends State<QuranPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Сравниваем без дефисов, апострофов и мягких знаков: человек набирает
  /// «аль бакара» или «албакара», а в списке «Аль-Бакара».
  String _fold(String v) => v
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r"[^а-яa-z0-9]"), '');

  /// Номера сур, подходящих под запрос. Ищем и по кириллице, и по латинице:
  /// пришедший из другого приложения набирает «al-baqara».
  List<int> get _found {
    final q = _fold(_query.text);
    final all = [for (var n = 1; n <= quran.totalSurahCount; n++) n];
    if (q.isEmpty) return all;
    return [
      for (final n in all)
        if ('$n' == q ||
            _fold(surahName(n)).contains(q) ||
            _fold(surahNameLatin(n)).contains(q))
          n,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(t('Коран')),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: t('Закладки и заметки'),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const BookmarksScreen())),
            icon: const Icon(Icons.bookmarks_outlined,
                color: AppColors.gold),
          ),
        ],
      ),
      body: DomeBackground(
        child: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top + 60),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon:
                      const Icon(Icons.search, size: 20, color: AppColors.gold),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: t('Очистить'),
                          onPressed: () {
                            _query.clear();
                            FocusScope.of(context).unfocus();
                            setState(() {});
                          },
                          icon: Icon(Icons.close,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.6)),
                        ),
                  hintText: t('Название суры или номер'),
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.32),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.gold),
                  ),
                ),
              ),
            ),
            Expanded(
              child: found.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
                      child: Text(
                        t('Такой суры нет.\nПопробуйте номер или другое написание.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.7)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      itemCount: found.length,
                      itemBuilder: (context, i) => _SurahTile(
                        number: found[i],
                        // Каскад только для первого экрана списка; дальше
                        // строки просто мягко проявляются при прокрутке.
                        delay: i < 9
                            ? Duration(milliseconds: 60 * i)
                            : Duration.zero,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurahTile extends StatelessWidget {
  final int number;
  final Duration delay;
  const _SurahTile({required this.number, required this.delay});

  @override
  Widget build(BuildContext context) {
    final n = number;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FadeSlideIn(
        delay: delay,
        duration: const Duration(milliseconds: 380),
        offset: const Offset(0, 18),
        child: Material(
          color: Colors.black.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SurahScreen(surah: n)),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.gold, width: 1.2),
                    ),
                    child: Text('$n',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.goldLight)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(surahName(n),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        Text(
                          '${t(quran.getPlaceOfRevelation(n) == "Makkah" ? "Мекка" : "Медина")} · ${verseCountLabel(quran.getVerseCount(n))}',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.65)),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    quran.getSurahNameArabic(n),
                    style: const TextStyle(
                        fontSize: 20, color: AppColors.goldLight),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
