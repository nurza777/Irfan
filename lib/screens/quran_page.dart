import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;

import '../theme.dart';
import 'surah_screen.dart';

/// Список 114 сур. Тап — чтение суры (арабский + перевод Кулиева).
class QuranPage extends StatelessWidget {
  const QuranPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('Коран',
                style:
                    TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              itemCount: quran.totalSurahCount,
              itemBuilder: (context, i) {
                final n = i + 1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppColors.cardGlass,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => SurahScreen(surah: n)),
                      ),
                      child: Padding(
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
                                    '${quran.getPlaceOfRevelation(n) == "Makkah" ? "Мекка" : "Медина"} · ${quran.getVerseCount(n)} аятов',
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
