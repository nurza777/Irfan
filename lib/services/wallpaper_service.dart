/// Свои обои вместо встроенного фото Каабы.
///
/// Файл копируется в папку приложения: снимок из галереи живёт во временном
/// каталоге, который система вправе очистить, и обои бы пропали.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WallpaperService extends ChangeNotifier {
  static const _key = 'wallpaper_path';

  /// Фон рисуется и на экранах вне AppScope, поэтому доступ — через синглтон.
  static final WallpaperService instance = WallpaperService._();
  WallpaperService._();

  SharedPreferences? _p;
  SharedPreferences get _prefs => _p!;

  /// Вызывается один раз при старте, до первого кадра.
  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  bool get ready => _p != null;

  /// Путь к своему фото или null — тогда показывается встроенное.
  String? get path {
    if (_p == null) return null;
    final p = _prefs.getString(_key);
    if (p == null) return null;
    // Файл могли удалить извне — не держимся за битый путь.
    if (!File(p).existsSync()) {
      _prefs.remove(_key);
      return null;
    }
    return p;
  }

  bool get isCustom => path != null;

  /// Просит выбрать фото и сохраняет его. true — обои сменились.
  Future<bool> pick({bool fromCamera = false}) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        // Ограничение по стороне: экран телефона всё равно меньше, а
        // полноразмерный снимок с камеры занимал бы десятки мегабайт.
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 90,
      );
      if (picked == null) return false;

      final docs = await getApplicationDocumentsDirectory();
      // Имя с меткой времени: iOS кэширует картинки по пути, и при
      // одинаковом имени на экране осталась бы прежняя.
      final dst = File('${docs.path}/wallpaper_'
          '${DateTime.now().millisecondsSinceEpoch}.jpg');
      await dst.writeAsBytes(await picked.readAsBytes(), flush: true);

      final old = _prefs.getString(_key);
      await _prefs.setString(_key, dst.path);
      if (old != null && old != dst.path) {
        try {
          await File(old).delete();
        } catch (_) {/* уже удалён — не важно */}
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('wallpaper pick error: $e');
      return false;
    }
  }

  /// Возвращает встроенное фото Каабы.
  Future<void> reset() async {
    final old = _prefs.getString(_key);
    await _prefs.remove(_key);
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {/* уже удалён */}
    }
    notifyListeners();
  }
}
