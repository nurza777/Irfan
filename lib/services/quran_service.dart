import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_translations.dart';
import 'reciters.dart';

/// Режим чтения Корана.
enum ReadingMode {
  sura('Сура', 'Список аятов одной суры'),
  page('Страница', 'Постранично, как в мусхафе');

  final String titleRu;
  final String subtitleRu;
  const ReadingMode(this.titleRu, this.subtitleRu);
}

/// Шрифт арабского текста Корана.
enum QuranFont {
  standard('Обычный', 'Системный наскх'),
  mushaf('Мусхаф', 'Как в печатном Коране');

  final String titleRu;
  final String subtitleRu;
  const QuranFont(this.titleRu, this.subtitleRu);

  /// fontFamily для Text; null — системный шрифт.
  String? get family => this == QuranFont.mushaf ? 'AmiriQuran' : null;
}

/// Что показывать в аяте.
class QuranDisplay {
  final bool arabic;
  final bool translation;
  final bool tajwid;
  const QuranDisplay({
    this.arabic = true,
    this.translation = true,
    this.tajwid = true,
  });

  QuranDisplay copyWith({bool? arabic, bool? translation, bool? tajwid}) =>
      QuranDisplay(
        arabic: arabic ?? this.arabic,
        translation: translation ?? this.translation,
        tajwid: tajwid ?? this.tajwid,
      );
}

/// Закладки, заметки и настройки Корана в SharedPreferences.
/// Меняется реактивно — экраны слушают [notifyListeners].
class QuranService extends ChangeNotifier {
  final SharedPreferences _prefs;
  QuranService(this._prefs);

  static Future<QuranService> create() async =>
      QuranService(await SharedPreferences.getInstance());

  static String key(int surah, int verse) => '$surah:$verse';

  // --- Настройки ---

  ReadingMode get mode =>
      ReadingMode.values.firstWhere(
        (m) => m.name == _prefs.getString('quran_mode'),
        orElse: () => ReadingMode.sura,
      );

  QuranDisplay get display => QuranDisplay(
        arabic: _prefs.getBool('quran_show_arabic') ?? true,
        translation: _prefs.getBool('quran_show_translation') ?? true,
        tajwid: _prefs.getBool('quran_tajwid') ?? true,
      );

  double get arabicFontSize => _prefs.getDouble('quran_font') ?? 26;

  QuranFont get arabicFont => QuranFont.values.firstWhere(
        (f) => f.name == _prefs.getString('quran_font_family'),
        orElse: () => QuranFont.standard,
      );

  Future<void> setArabicFont(QuranFont f) async {
    await _prefs.setString('quran_font_family', f.name);
    notifyListeners();
  }

  QuranReciter get reciter => reciterById(_prefs.getString('quran_reciter'));

  Future<void> setReciter(QuranReciter r) async {
    await _prefs.setString('quran_reciter', r.id);
    notifyListeners();
  }

  // --- Перевод ---

  /// Декодированные тексты переводов из ассетов, кэш по id.
  final Map<String, Map<String, String>> _trCache = {};
  String? _trLoading;

  QuranTranslation get translation =>
      translationById(_prefs.getString('quran_translation'));

  /// Готов ли текст выбранного перевода к показу.
  bool get translationReady => _trCache.containsKey(translation.id);

  Future<void> setTranslation(QuranTranslation t) async {
    await _prefs.setString('quran_translation', t.id);
    notifyListeners();
    await ensureTranslationLoaded(t);
  }

  /// Подгружает и распаковывает gzip-ассет перевода один раз, затем уведомляет.
  Future<void> ensureTranslationLoaded(QuranTranslation t) async {
    if (_trCache.containsKey(t.id) || _trLoading == t.id) {
      return;
    }
    _trLoading = t.id;
    try {
      final data = await rootBundle.load(t.asset);
      // Распаковка и разбор — в отдельном потоке: это 1,7 МБ текста и 6236
      // записей, на телефоне десятки миллисекунд, и делать их в главном
      // потоке значит подвесить экран ровно в момент открытия суры.
      _trCache[t.id] = await compute(_decodeTranslation, data.buffer.asUint8List());
    } catch (e) {
      debugPrint('QuranService: failed to load translation ${t.id}: $e');
    } finally {
      _trLoading = null;
      notifyListeners();
    }
  }

  /// Текст перевода аята для выбранного перевода. Пустая строка — если
  /// ассет ещё грузится.
  String translationOf(int surah, int verse) =>
      _trCache[translation.id]?['$surah:$verse'] ?? '';

  Future<void> setMode(ReadingMode m) async {
    await _prefs.setString('quran_mode', m.name);
    notifyListeners();
  }

  Future<void> setDisplay(QuranDisplay d) async {
    await _prefs.setBool('quran_show_arabic', d.arabic);
    await _prefs.setBool('quran_show_translation', d.translation);
    await _prefs.setBool('quran_tajwid', d.tajwid);
    notifyListeners();
  }

  Future<void> setArabicFontSize(double v) async {
    await _prefs.setDouble('quran_font', v.clamp(20, 40));
    notifyListeners();
  }

  // --- Закладки ---

  Set<String> get _bookmarks =>
      (_prefs.getStringList('quran_bookmarks') ?? []).toSet();

  bool isBookmarked(int surah, int verse) =>
      _bookmarks.contains(key(surah, verse));

  List<String> get bookmarks {
    final list = _bookmarks.toList();
    // Сортировка по суре, затем по аяту.
    list.sort((a, b) {
      final pa = a.split(':').map(int.parse).toList();
      final pb = b.split(':').map(int.parse).toList();
      return pa[0] != pb[0] ? pa[0] - pb[0] : pa[1] - pb[1];
    });
    return list;
  }

  Future<void> toggleBookmark(int surah, int verse) async {
    final set = _bookmarks;
    final k = key(surah, verse);
    set.contains(k) ? set.remove(k) : set.add(k);
    await _prefs.setStringList('quran_bookmarks', set.toList());
    notifyListeners();
  }

  // --- Заметки ---

  Map<String, String> get _notes {
    final raw = _prefs.getString('quran_notes');
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  String? noteOf(int surah, int verse) => _notes[key(surah, verse)];
  bool hasNote(int surah, int verse) =>
      (_notes[key(surah, verse)] ?? '').isNotEmpty;

  /// Аяты с заметками (для списка), отсортированы.
  List<String> get notedVerses {
    final list = _notes.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => e.key)
        .toList();
    list.sort((a, b) {
      final pa = a.split(':').map(int.parse).toList();
      final pb = b.split(':').map(int.parse).toList();
      return pa[0] != pb[0] ? pa[0] - pb[0] : pa[1] - pb[1];
    });
    return list;
  }

  Future<void> setNote(int surah, int verse, String text) async {
    final notes = _notes;
    final k = key(surah, verse);
    if (text.trim().isEmpty) {
      notes.remove(k);
    } else {
      notes[k] = text.trim();
    }
    await _prefs.setString('quran_notes', jsonEncode(notes));
    notifyListeners();
  }
}

/// Выполняется в отдельном потоке — только чистые вычисления, без обращений
/// к настройкам и ассетам (в другом потоке их бы не было).
Map<String, String> _decodeTranslation(Uint8List bytes) =>
    Map<String, String>.from(
        jsonDecode(utf8.decode(gzip.decode(bytes))) as Map);
