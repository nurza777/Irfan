/// Перевод/транслитерация Корана. [asset] == null — берётся из пакета `quran`
/// (Кулиев, офлайн по умолчанию); иначе это gzip-JSON `{"сура:аят": текст}`
/// в ассетах (скачаны с alquran.cloud, проект Tanzil — открытые тексты).
class QuranTranslation {
  final String id;
  final String name;
  final String subtitle;
  final String? asset;
  const QuranTranslation({
    required this.id,
    required this.name,
    required this.subtitle,
    this.asset,
  });
}

const quranTranslations = <QuranTranslation>[
  QuranTranslation(
      id: 'kuliev', name: 'Эльмир Кулиев', subtitle: 'Русский · смысловой'),
  QuranTranslation(
      id: 'abuadel',
      name: 'Абу Адель',
      subtitle: 'Русский · смысловой',
      asset: 'assets/quran/tr_ru_abuadel.json.gz'),
  QuranTranslation(
      id: 'osmanov',
      name: 'Магомед-Нури Османов',
      subtitle: 'Русский',
      asset: 'assets/quran/tr_ru_osmanov.json.gz'),
  QuranTranslation(
      id: 'porokhova',
      name: 'Валерия Порохова',
      subtitle: 'Русский · поэтический',
      asset: 'assets/quran/tr_ru_porokhova.json.gz'),
  QuranTranslation(
      id: 'krachkovsky',
      name: 'Игнатий Крачковский',
      subtitle: 'Русский · академический',
      asset: 'assets/quran/tr_ru_krachkovsky.json.gz'),
  QuranTranslation(
      id: 'sablukov',
      name: 'Гордий Саблуков',
      subtitle: 'Русский · классический',
      asset: 'assets/quran/tr_ru_sablukov.json.gz'),
  QuranTranslation(
      id: 'muntahab',
      name: 'Аль-Мунтахаб',
      subtitle: 'Русский · с толкованием',
      asset: 'assets/quran/tr_ru_muntahab.json.gz'),
  QuranTranslation(
      id: 'translit',
      name: 'Транслитерация',
      subtitle: 'Кириллица · чтение',
      asset: 'assets/quran/tr_ru_transliteration.json.gz'),
  QuranTranslation(
      id: 'kazakh',
      name: 'Халифа Алтай',
      subtitle: 'Қазақша',
      asset: 'assets/quran/tr_kk_khalifahaltai.json.gz'),
];

QuranTranslation translationById(String? id) => quranTranslations.firstWhere(
      (t) => t.id == id,
      orElse: () => quranTranslations.first,
    );
