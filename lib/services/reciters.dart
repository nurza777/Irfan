import 'package:quran/quran.dart' as quran;

/// Чтец Корана: [edition] — идентификатор на cdn.islamic.network,
/// [bitrate] — доступный на CDN битрейт (у части чтецов только 64).
class QuranReciter {
  final String id;
  final String name;
  final String edition;
  final int bitrate;
  const QuranReciter({
    required this.id,
    required this.name,
    required this.edition,
    required this.bitrate,
  });

  /// URL аудио аята. Глобальный номер аята (1–6236) берём из пакета `quran`
  /// (его `getAudioURLByVerse` считает его корректно), меняя лишь чтеца и
  /// битрейт: `.../audio/{bitrate}/{edition}/{globalAyah}.mp3`.
  String audioUrl(int surah, int verse) {
    final globalAyah = quran
        .getAudioURLByVerse(surah, verse)
        .split('/')
        .last
        .replaceAll('.mp3', '');
    return 'https://cdn.islamic.network/quran/audio/'
        '$bitrate/$edition/$globalAyah.mp3';
  }
}

/// Известные чтецы (все проверены на CDN 2026-07-24). Первый — по умолчанию.
const quranReciters = <QuranReciter>[
  QuranReciter(
      id: 'alafasy',
      name: 'Мишари Рашид аль-Афаси',
      edition: 'ar.alafasy',
      bitrate: 128),
  QuranReciter(
      id: 'abdulbasit',
      name: 'Абдуль-Басит Абдуссамад',
      edition: 'ar.abdulbasitmurattal',
      bitrate: 64),
  QuranReciter(
      id: 'sudais',
      name: 'Абдуррахман ас-Судайс',
      edition: 'ar.abdurrahmaansudais',
      bitrate: 64),
  QuranReciter(
      id: 'husary',
      name: 'Махмуд Халиль аль-Хусари',
      edition: 'ar.husary',
      bitrate: 128),
  QuranReciter(
      id: 'minshawi',
      name: 'Мухаммад Сиддик аль-Миншави',
      edition: 'ar.minshawi',
      bitrate: 128),
  QuranReciter(
      id: 'shaatree',
      name: 'Абу Бакр аш-Шатри',
      edition: 'ar.shaatree',
      bitrate: 128),
  QuranReciter(
      id: 'maher',
      name: 'Махир аль-Муайкли',
      edition: 'ar.mahermuaiqly',
      bitrate: 128),
  QuranReciter(
      id: 'ajamy',
      name: 'Ахмад аль-Аджами',
      edition: 'ar.ahmedajamy',
      bitrate: 128),
  QuranReciter(
      id: 'hudhaify',
      name: 'Али аль-Хузайфи',
      edition: 'ar.hudhaify',
      bitrate: 128),
  QuranReciter(
      id: 'shuraym',
      name: 'Сауд аш-Шурайм',
      edition: 'ar.saoodshuraym',
      bitrate: 64),
];

QuranReciter reciterById(String? id) => quranReciters.firstWhere(
      (r) => r.id == id,
      orElse: () => quranReciters.first,
    );
