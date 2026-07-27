import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;

/// Один зикр/дуа: арабский текст, транслитерация, смысл, рекомендованное
/// число повторов и источник.
///
/// Точность арабского — приоритет: коранические азкары берутся напрямую из
/// пакета `quran`, короткие зикры — те же выверенные строки, что в счётчике
/// зикров ([ZikrService]). Ничего не набирается «от руки».
class Azkar {
  final String arabic;
  final String translit;
  final String meaning;
  final int count;
  final String source;
  const Azkar({
    required this.arabic,
    this.translit = '',
    required this.meaning,
    this.count = 1,
    this.source = '',
  });
}

class AzkarCategory {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Azkar> items;
  const AzkarCategory({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.items,
  });
}

/// Полный текст суры (аяты через разделитель) — из пакета `quran`.
String _surah(int s) {
  final b = StringBuffer();
  for (var v = 1; v <= quran.getVerseCount(s); v++) {
    b.write(quran.getVerse(s, v));
    b.write(' ${quran.getVerseEndSymbol(v)} ');
  }
  return b.toString().trim();
}

/// Категории азкаров. Строится при вызове (тянет коранический текст из пакета).
List<AzkarCategory> buildAzkarCategories() => [
      AzkarCategory(
        title: 'Утро и вечер',
        subtitle: 'Защитные азкары (аль-муаввизат)',
        icon: Icons.wb_twilight,
        items: [
          Azkar(
            arabic: quran.getVerse(2, 255),
            meaning: 'Аят аль-Курси — величайший аят о власти и знании Аллаха. '
                'Читается для защиты утром и вечером.',
            count: 1,
            source: 'Коран 2:255',
          ),
          Azkar(
            arabic: _surah(112),
            meaning: 'Сура «Аль-Ихлас» (Искренность).',
            count: 3,
            source: 'Коран, сура 112',
          ),
          Azkar(
            arabic: _surah(113),
            meaning: 'Сура «Аль-Фаляк» (Рассвет) — защита от зла творений.',
            count: 3,
            source: 'Коран, сура 113',
          ),
          Azkar(
            arabic: _surah(114),
            meaning: 'Сура «Ан-Нас» (Люди) — защита от наваждений.',
            count: 3,
            source: 'Коран, сура 114',
          ),
        ],
      ),
      const AzkarCategory(
        title: 'После намаза',
        subtitle: 'Тасбих: 33 · 33 · 34',
        icon: Icons.self_improvement,
        items: [
          Azkar(
            arabic: 'سُبْحَانَ ٱللَّٰهِ',
            translit: 'СубханаЛлах',
            meaning: 'Пречист Аллах.',
            count: 33,
          ),
          Azkar(
            arabic: 'ٱلْحَمْدُ لِلَّٰهِ',
            translit: 'Альхамдулиллях',
            meaning: 'Хвала Аллаху.',
            count: 33,
          ),
          Azkar(
            arabic: 'ٱللَّٰهُ أَكْبَرُ',
            translit: 'Аллаху акбар',
            meaning: 'Аллах велик.',
            count: 34,
          ),
          Azkar(
            arabic: 'لَا إِلَٰهَ إِلَّا ٱللَّٰهُ',
            translit: 'Ля иляха илляЛлах',
            meaning: 'Нет божества, кроме Аллаха.',
            count: 1,
          ),
        ],
      ),
      const AzkarCategory(
        title: 'Поминание и мольба',
        subtitle: 'В течение дня',
        icon: Icons.favorite_outline,
        items: [
          Azkar(
            arabic: 'أَسْتَغْفِرُ ٱللَّٰهَ',
            translit: 'Астагфируллах',
            meaning: 'Прошу прощения у Аллаха.',
            count: 33,
          ),
          Azkar(
            arabic: 'ٱللَّٰهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ',
            translit: 'Аллахумма салли аля Мухаммад',
            meaning: 'О Аллах, благослови Мухаммада ﷺ.',
            count: 10,
          ),
          Azkar(
            arabic: 'حَسْبُنَا ٱللَّٰهُ وَنِعْمَ ٱلْوَكِيلُ',
            translit: 'ХасбунаЛлаху ва ниʼмаль-вакиль',
            meaning: 'Достаточно нам Аллаха, Он — лучший Покровитель.',
            count: 7,
          ),
        ],
      ),
    ];
