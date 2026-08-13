import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;

import '../services/lang.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import 'bookmarks_screen.dart';
import 'surah_screen.dart';

/// Список 114 сур — отдельный экран (открывается кнопкой «КОРАН»).
/// Тап по суре — чтение (арабский + перевод Azan.ru).
class QuranPage extends StatelessWidget {
  const QuranPage({super.key});

  @override
  Widget build(BuildContext context) {
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
        child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                  20, MediaQuery.of(context).padding.top + 66, 20, 16),
              itemCount: quran.totalSurahCount,
              itemBuilder: (context, i) {
                final n = i + 1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FadeSlideIn(
                    // Каскад только для первого экрана списка; дальше
                    // строки просто мягко проявляются при прокрутке.
                    delay: i < 9
                        ? Duration(milliseconds: 60 * i)
                        : Duration.zero,
                    duration: const Duration(milliseconds: 380),
                    offset: const Offset(0, 18),
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => SurahScreen(surah: n)),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color:
                                    Colors.white.withValues(alpha: 0.10)),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppColors.gold, width: 1.2),
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(quran.getSurahName(n),
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                      '${t(quran.getPlaceOfRevelation(n) == "Makkah" ? "Мекка" : "Медина")} · ${quran.getVerseCount(n)} ${appLang == Lang.ky ? 'аят' : 'аятов'}',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.white
                                              .withValues(alpha: 0.65)),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                quran.getSurahNameArabic(n),
                                style: const TextStyle(
                                    fontSize: 20,
                                    color: AppColors.goldLight),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      ),
    );
  }
}
