import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_state.dart';
import '../services/lang.dart';
import '../services/media_link.dart';
import '../services/news_service.dart';
import '../theme.dart';

/// Просмотр вложения новости во весь экран: фото можно приблизить,
/// видео — посмотреть.
///
/// Отдельный экран, а не плеер урока: у урока есть курс, следующий урок и
/// запоминание места остановки — к объявлению всё это неприменимо, а лишние
/// зависимости пришлось бы обходить заглушками.
class NewsMediaScreen extends StatelessWidget {
  final NewsAttachment media;
  final String title;

  const NewsMediaScreen({super.key, required this.media, this.title = ''});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontSize: 16)),
      ),
      body: Center(
        child: media.isVideo
            ? _Video(url: media.url)
            : InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(
                  media.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const _Failed(),
                ),
              ),
      ),
    );
  }
}

/// Проигрыватель видео из новости: пуск, пауза и перемотка.
class _Video extends StatefulWidget {
  final String url;
  const _Video({required this.url});

  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _awake = false;
  bool _started = false;

  /// Открываем здесь, а не в initState: подписанная ссылка берётся из
  /// AppScope, а к нему нельзя обращаться, пока initState не завершился.
  /// Метод вызывается и при смене зависимостей — поэтому флаг.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _open();
  }

  Future<void> _open() async {
    // Ссылка подписывается на время просмотра — так же, как у уроков.
    final src = await MediaLink.playable(
        widget.url, mounted ? AppScope.of(context).auth : null);
    if (!mounted) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(src));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
      await c.play();
      // Пока идёт видео, экран не гаснет; снимаем блокировку при выходе.
      await WakelockPlus.enable();
      _awake = true;
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    if (_awake) WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const _Failed();
    final c = _c;
    if (c == null) {
      return const CircularProgressIndicator(color: AppColors.gold);
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          child: GestureDetector(
            onTap: () => setState(
                () => c.value.isPlaying ? c.pause() : c.play()),
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(c),
                if (!c.value.isPlaying)
                  const Icon(Icons.play_arrow,
                      size: 64, color: Colors.white70),
              ],
            ),
          ),
        ),
        VideoProgressIndicator(
          c,
          allowScrubbing: true,
          colors: const VideoProgressColors(playedColor: AppColors.gold),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_off, size: 48, color: Colors.white54),
        const SizedBox(height: 12),
        Text(t('Не удалось загрузить'),
            style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
