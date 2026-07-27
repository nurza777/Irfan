import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tts/flutter_tts.dart';

/// Озвучка имён Аллаха и зикров. Сначала пробует настоящую запись чтеца из
/// ассетов (assets/audio/…); если файла нет — системный синтез речи
/// (арабский голос, а без него — русский текст-фолбэк). Всё офлайн.
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final _player = AudioPlayer();
  final _tts = FlutterTts();
  bool _ready = false;
  String? _arLocale; // выбранный арабский локаль или null, если голоса нет

  /// id текущего озвучиваемого элемента (null — тишина). Кнопки подписываются,
  /// чтобы показывать «стоп» только у своего элемента.
  final ValueNotifier<String?> speakingId = ValueNotifier(null);

  Future<void> _init() async {
    if (_ready) return;
    _player.onPlayerComplete.listen((_) => speakingId.value = null);
    try {
      await _tts.setSharedInstance(true);
      // Категория playback — чтобы озвучка звучала и при выключенном
      // переключателе звонка на iPhone.
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.duckOthers],
        IosTextToSpeechAudioMode.spokenAudio,
      );
    } catch (_) {
      // Не iOS — настройки категории недоступны, это нормально.
    }
    for (final locale in const ['ar-SA', 'ar-001', 'ar-AE', 'ar-EG', 'ar']) {
      if (await _tts.isLanguageAvailable(locale) == true) {
        _arLocale = locale;
        break;
      }
    }
    await _tts.setSpeechRate(0.42);
    await _tts.awaitSpeakCompletion(true);
    _tts.setCompletionHandler(() => speakingId.value = null);
    _tts.setCancelHandler(() => speakingId.value = null);
    _ready = true;
  }

  /// Озвучить элемент [id]. Порядок: запись [asset] (путь внутри assets/,
  /// например `audio/names/1.mp3`) → арабский TTS [arabic] → русский TTS
  /// [fallback]. Повторный вызов с тем же [id] во время звучания — стоп.
  Future<void> speak(String id, String arabic,
      {String? asset, String? fallback}) async {
    await _init();
    if (speakingId.value == id) {
      await stop();
      return;
    }
    await stop();
    if (asset != null && await _assetExists('assets/$asset')) {
      speakingId.value = id;
      await _player.play(AssetSource(asset));
      return;
    }
    final useArabic = _arLocale != null && arabic.trim().isNotEmpty;
    final text = useArabic ? arabic : (fallback ?? arabic);
    if (text.trim().isEmpty) return;
    await _tts.setLanguage(useArabic ? _arLocale! : 'ru-RU');
    speakingId.value = id;
    await _tts.speak(text);
  }

  Future<bool> _assetExists(String key) async {
    try {
      await rootBundle.load(key);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    speakingId.value = null;
    await _player.stop();
    await _tts.stop();
  }
}
