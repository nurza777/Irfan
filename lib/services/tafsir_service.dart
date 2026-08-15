import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Толкование Корана с azan.ru — офлайн, внутри приложения.
///
/// Материалы взяты с разрешения правообладателя (исламский
/// информационно-образовательный портал Azan.ru); указание источника
/// обязательно и показывается под каждым толкованием — см. [sourceUrl].
///
/// **Толкование групповое.** У azan.ru текст даётся не к каждому аяту
/// по отдельности, а к смысловой группе: в суре «аль-Адият» один текст
/// объясняет аяты 1–5, следующий — 6–10. Поэтому поиск идёт по диапазону,
/// а не по точному номеру: иначе человек тапал бы по третьему аяту и
/// получал пустоту, хотя объяснение стоит парой строк выше.
class TafsirService {
  TafsirService._();
  static final instance = TafsirService._();

  static const _asset = 'assets/quran/tafsir_azan.json.gz';

  /// Дата выгрузки: копия устаревает, когда портал правит текст у себя.
  static const snapshotDate = '10 августа 2026';

  Map<String, dynamic>? _data;
  Future<void>? _loading;

  /// Загружает и распаковывает ассет один раз. Ленивo: 1,2 МБ в архиве и
  /// около 5 МБ текста в памяти незачем держать у того, кто тафсир не
  /// открывает.
  Future<void> _ensure() {
    if (_data != null) return Future.value();
    return _loading ??= () async {
      try {
        final raw = await rootBundle.load(_asset);
        // Пять мегабайт текста: в главном потоке это заметная пауза при
        // первом открытии толкования, поэтому распаковываем в отдельном.
        _data = await compute(_decodeTafsir, raw.buffer.asUint8List());
      } catch (e) {
        debugPrint('tafsir load error: $e');
        _data = const {};
      }
    }();
  }

  /// Толкование для аята. null — для этого аята текста нет (так бывает у
  /// сур, начинающихся с разрозненных букв: «Алиф Лям Мим Сад»).
  Future<TafsirEntry?> forVerse(int surah, int verse) async {
    await _ensure();
    final sura = _data?['$surah'];
    if (sura is! Map) return null;
    final intro = (sura['intro'] as String?) ?? '';
    for (final g in (sura['groups'] as List? ?? const [])) {
      if (g is! Map) continue;
      final from = (g['from'] as num?)?.toInt() ?? 0;
      final to = (g['to'] as num?)?.toInt() ?? 0;
      if (verse >= from && verse <= to) {
        return TafsirEntry(
          surah: surah,
          from: from,
          to: to,
          text: (g['text'] as String?) ?? '',
          intro: intro,
          slug: (sura['slug'] as String?) ?? '',
        );
      }
    }
    // Толкования к самому аяту нет — отдаём вступление к суре, если оно есть:
    // там обычно и лежит то, что относится к её началу.
    if (intro.isEmpty) return null;
    return TafsirEntry(
      surah: surah,
      from: 0,
      to: 0,
      text: '',
      intro: intro,
      slug: (sura['slug'] as String?) ?? '',
    );
  }

  /// Есть ли вообще толкование для суры (для показа кнопки).
  Future<bool> hasSurah(int surah) async {
    await _ensure();
    final sura = _data?['$surah'];
    return sura is Map && (sura['groups'] as List? ?? const []).isNotEmpty;
  }
}

/// Толкование к группе аятов.
class TafsirEntry {
  final int surah;

  /// Диапазон аятов, который объясняет [text]. 0 — текста к аяту нет и
  /// показывается только [intro].
  final int from;
  final int to;
  final String text;

  /// Вступление к суре: где ниспослана, сколько аятов, достоинства.
  final String intro;

  /// Имя суры в адресах azan.ru — для ссылки на источник.
  final String slug;

  const TafsirEntry({
    required this.surah,
    required this.from,
    required this.to,
    required this.text,
    required this.intro,
    required this.slug,
  });

  bool get hasText => text.isNotEmpty;

  /// Заголовок: к скольким аятам относится текст.
  String get rangeLabel {
    if (from == 0) return '';
    return from == to ? 'аят $from' : 'аяты $from–$to';
  }

  /// Ссылка на страницу этой суры на azan.ru.
  String get sourceUrl =>
      slug.isEmpty ? 'https://azan.ru/tafsir' : 'https://azan.ru/tafsir/$slug';
}

/// Считается в отдельном потоке: только распаковка и разбор.
Map<String, dynamic> _decodeTafsir(Uint8List bytes) =>
    jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
