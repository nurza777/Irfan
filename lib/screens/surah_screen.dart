import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;

import '../theme.dart';

/// Чтение суры: арабский текст + русский перевод (Э. Кулиев).
class SurahScreen extends StatelessWidget {
  final int surah;
  const SurahScreen({super.key, required this.surah});

  @override
  Widget build(BuildContext context) {
    final verseCount = quran.getVerseCount(surah);
    // Басмала показывается перед всеми сурами, кроме 1-й (она — её аят) и 9-й.
    final showBasmala = surah != 1 && surah != 9;

    return Scaffold(
      backgroundColor: AppColors.skyBottom,
      appBar: AppBar(
        backgroundColor: AppColors.domeDark,
        title: Column(
          children: [
            Text(quran.getSurahName(surah),
                style: const TextStyle(fontSize: 18)),
            Text(quran.getSurahNameArabic(surah),
                style: const TextStyle(
                    fontSize: 14, color: AppColors.goldLight)),
          ],
        ),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: verseCount + (showBasmala ? 1 : 0),
        itemBuilder: (context, i) {
          if (showBasmala && i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                quran.basmala,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 24, color: AppColors.goldLight),
              ),
            );
          }
          final verse = showBasmala ? i : i + 1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: AppColors.cardGlass,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      quran.getVerse(surah, verse, verseEndSymbol: true),
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontSize: 22, height: 1.8),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$verse. ${quran.getVerseTranslation(surah, verse, translation: quran.Translation.ruKuliev)}',
                      style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
