import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;

/// Озвучка настоящими записями — и только ими.
///
/// Раньше при отсутствии записи включался системный синтез речи. Звучал он
/// механически и на арабском читал плохо, а в приложении о поклонении это
/// хуже, чем тишина. Теперь: есть запись — звучит, нет записи — кнопки
/// озвучки просто нет.
///
/// Всё офлайн, из ассетов. Аудио Корана живёт отдельно (свои чтецы и
/// загрузка, см. QuranAudioCache) и сюда не относится.
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final _player = AudioPlayer();
  bool _ready = false;

  /// Какие записи вообще есть в сборке. Заполняется один раз из описи
  /// ассетов, чтобы экраны могли СИНХРОННО решить, показывать ли кнопку:
  /// проверять наличие файла в момент отрисовки нельзя — это асинхронно.
  Set<String> _available = const {};
  bool _catalogLoaded = false;

  /// id текущего озвучиваемого элемента (null — тишина). Кнопки подписываются,
  /// чтобы показывать «стоп» только у своего элемента.
  final ValueNotifier<String?> speakingId = ValueNotifier(null);

  /// Читает опись ассетов. Вызывать один раз при запуске, до первого экрана.
  Future<void> loadCatalog() async {
    if (_catalogLoaded) return;
    _catalogLoaded = true;
    try {
      // Именно AssetManifest, а не чтение AssetManifest.json: файла с таким
      // именем в сборке уже нет, опись давно бинарная, и попытка прочитать
      // её как текст тихо давала пустой список — кнопки озвучки пропадали
      // даже там, где запись есть.
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _available = manifest
          .listAssets()
          .where((k) => k.startsWith('assets/audio/'))
          .map((k) => k.substring('assets/'.length))
          .toSet();
    } catch (e) {
      debugPrint('voice catalog error: $e');
      _available = const {};
    }
  }

  /// Есть ли запись для этого пути (внутри assets/, например
  /// `audio/zikr/subhanallah.mp3`).
  bool hasRecording(String asset) => _available.contains(asset);

  Future<void> _init() async {
    if (_ready) return;
    _player.onPlayerComplete.listen((_) => speakingId.value = null);
    // Категория playback — чтобы озвучка звучала и при выключенном
    // переключателе звонка на iPhone.
    await _player.setAudioContext(AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.duckOthers},
      ),
    ));
    _ready = true;
  }

  /// Проигрывает запись [asset]. Повторный вызов с тем же [id] во время
  /// звучания — стоп. Если записи нет, ничего не происходит: кнопку в таком
  /// случае и не показывают.
  Future<void> speak(String id, String asset) async {
    await _init();
    if (speakingId.value == id) {
      await stop();
      return;
    }
    await stop();
    if (!hasRecording(asset)) return;
    speakingId.value = id;
    await _player.play(AssetSource(asset));
  }

  Future<void> stop() async {
    await _player.stop();
    speakingId.value = null;
  }
}
