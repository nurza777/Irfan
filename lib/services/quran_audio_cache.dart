/// Оффлайн-аудио Корана: скачивание суры целиком и воспроизведение без сети.
///
/// Файлы лежат в `Documents/quran_audio/<чтец>/<сура>/<аят>.mp3`. Чтец входит
/// в путь, потому что у каждого своя запись — переключение чтеца не должно
/// подсовывать чужой голос.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:quran/quran.dart' as quran;

import 'reciters.dart';

/// Ход загрузки одной суры.
class DownloadProgress {
  final int done;
  final int total;
  const DownloadProgress(this.done, this.total);
  double get fraction => total == 0 ? 0 : done / total;
}

class QuranAudioCache {
  QuranAudioCache._();
  static final QuranAudioCache instance = QuranAudioCache._();

  Directory? _root;

  /// Суры, которые скачиваются прямо сейчас: id → прогресс.
  final ValueNotifier<Map<String, DownloadProgress>> active =
      ValueNotifier({});

  /// Меняется после любой загрузки/удаления — чтобы экраны перерисовались.
  final ValueNotifier<int> revision = ValueNotifier(0);

  final Set<String> _cancelled = {};

  static String keyOf(QuranReciter r, int surah) => '${r.id}/$surah';

  Future<Directory> _dir() async {
    final r = _root;
    if (r != null) return r;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/quran_audio');
    await d.create(recursive: true);
    _root = d;
    return d;
  }

  Future<String> _versePath(QuranReciter r, int surah, int verse) async {
    final d = await _dir();
    return '${d.path}/${r.id}/$surah/$verse.mp3';
  }

  /// Локальный файл аята или null, если не скачан.
  Future<String?> localVerse(QuranReciter r, int surah, int verse) async {
    final p = await _versePath(r, surah, verse);
    return await File(p).exists() ? p : null;
  }

  /// Скачана ли сура целиком (по числу файлов).
  Future<bool> isSurahDownloaded(QuranReciter r, int surah) async {
    final d = await _dir();
    final dir = Directory('${d.path}/${r.id}/$surah');
    if (!await dir.exists()) return false;
    final count = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.mp3'))
        .length;
    return count >= quran.getVerseCount(surah);
  }

  /// Сколько занимает скачанное этим чтецом, в байтах.
  Future<int> sizeFor(QuranReciter r) async {
    final d = await _dir();
    final dir = Directory('${d.path}/${r.id}');
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is File) {
        total += await e.length();
      }
    }
    return total;
  }

  /// Общий объём кэша по всем чтецам.
  Future<int> totalSize() async {
    final d = await _dir();
    if (!await d.exists()) return 0;
    var total = 0;
    await for (final e in d.list(recursive: true)) {
      if (e is File) {
        total += await e.length();
      }
    }
    return total;
  }

  void cancel(QuranReciter r, int surah) => _cancelled.add(keyOf(r, surah));

  /// Скачивает все аяты суры. Уже имеющиеся файлы пропускает, так что
  /// прерванную загрузку можно продолжить повторным запуском.
  Future<bool> downloadSurah(QuranReciter r, int surah) async {
    final key = keyOf(r, surah);
    if (active.value.containsKey(key)) return false;
    _cancelled.remove(key);

    final total = quran.getVerseCount(surah);
    _setProgress(key, DownloadProgress(0, total));

    final d = await _dir();
    await Directory('${d.path}/${r.id}/$surah').create(recursive: true);
    final client = http.Client();
    var ok = true;
    try {
      for (var v = 1; v <= total; v++) {
        if (_cancelled.contains(key)) {
          ok = false;
          break;
        }
        final path = '${d.path}/${r.id}/$surah/$v.mp3';
        final file = File(path);
        if (!await file.exists()) {
          final resp = await client
              .get(Uri.parse(r.audioUrl(surah, v)))
              .timeout(const Duration(seconds: 30));
          if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
            ok = false;
            break;
          }
          // Пишем во временный файл и переименовываем: обрыв связи не
          // оставит «половинку», которую потом сочтут скачанной.
          final tmp = File('$path.part');
          await tmp.writeAsBytes(resp.bodyBytes, flush: true);
          await tmp.rename(path);
        }
        _setProgress(key, DownloadProgress(v, total));
      }
    } catch (e) {
      debugPrint('quran audio download error: $e');
      ok = false;
    } finally {
      client.close();
      _clearProgress(key);
      _cancelled.remove(key);
      revision.value++;
    }
    return ok;
  }

  /// Удаляет скачанную суру.
  Future<void> deleteSurah(QuranReciter r, int surah) async {
    final d = await _dir();
    final dir = Directory('${d.path}/${r.id}/$surah');
    if (await dir.exists()) await dir.delete(recursive: true);
    revision.value++;
  }

  /// Удаляет весь оффлайн-кэш аудио.
  Future<void> deleteAll() async {
    final d = await _dir();
    if (await d.exists()) await d.delete(recursive: true);
    _root = null;
    revision.value++;
  }

  void _setProgress(String key, DownloadProgress p) {
    active.value = {...active.value, key: p};
  }

  void _clearProgress(String key) {
    final m = {...active.value}..remove(key);
    active.value = m;
  }
}

/// «12,4 МБ» — размер для показа в интерфейсе.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
}
