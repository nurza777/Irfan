import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/asmaul_husna.dart';
import '../services/voice_service.dart';
import '../services/lang.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import 'quiz_screen.dart';

/// 99 имён Аллаха — круглый листаемый дизайн (как счётчик зикров):
/// одно имя в круге, свайп влево/вправо. Плюс кнопка викторины.
class NamesScreen extends StatefulWidget {
  const NamesScreen({super.key});

  @override
  State<NamesScreen> createState() => _NamesScreenState();
}

class _NamesScreenState extends State<NamesScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    VoiceService.instance.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Column(
          children: [
            Text(t('99 имён Аллаха'), style: TextStyle(fontSize: 18)),
            Text(t('аль-Асма аль-Хусна'),
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.goldLight.withValues(alpha: 0.9))),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const QuizScreen())),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.goldLight),
              icon: const Icon(Icons.quiz_outlined, size: 20),
              label: Text(t('Викторина')),
            ),
          ),
        ],
      ),
      body: DomeBackground(
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + 56),
              Text((appLang == Lang.ky ? 'Ысым ${_index + 1} / ${asmaulHusna.length}' : 'Имя ${_index + 1} из ${asmaulHusna.length}'),
                  style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.8))),
              Expanded(
                // Круг и кольцо зафиксированы, листается только содержимое.
                child: Center(
                  child: SizedBox(
                    width: 300,
                    height: 300,
                    child: CustomPaint(
                      painter: _RingPainter(),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: GlassCard(
                          radius: 140,
                          darkness: 0.32,
                          child: ClipOval(
                            child: PageView.builder(
                              controller: _controller,
                              itemCount: asmaulHusna.length,
                              onPageChanged: (i) {
                                VoiceService.instance.stop();
                                setState(() => _index = i);
                              },
                              itemBuilder: (context, i) =>
                                  _NameContent(name: asmaulHusna[i]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _ListenButton(index: _index),
              const SizedBox(height: 14),
              _NavBar(
                index: _index,
                total: asmaulHusna.length,
                onPrev: _index > 0
                    ? () => _controller.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut)
                    : null,
                onNext: _index < asmaulHusna.length - 1
                    ? () => _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut)
                    : null,
              ),
              const SizedBox(height: 6),
              Text(t('Листайте влево или вправо'),
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.55))),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка «Слушать»: озвучивает арабское имя, во время речи — «Стоп».
class _ListenButton extends StatelessWidget {
  final int index;
  const _ListenButton({required this.index});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: VoiceService.instance.speakingId,
      builder: (context, speaking, _) {
        final id = 'name_$index';
        final active = speaking == id;
        return PressableScale(
          onTap: () => VoiceService.instance
              .speak(id, 'audio/names/${asmaulHusna[index].number}.mp3'),
          child: GlassCard(
            radius: 24,
            blur: 10,
            darkness: 0.18,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    active
                        ? Icons.stop_rounded
                        : Icons.volume_up_rounded,
                    size: 22,
                    color: AppColors.goldLight),
                const SizedBox(width: 8),
                Text(active ? t('Стоп') : t('Слушать'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.goldLight)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Содержимое круга для одного имени (то, что листается внутри).
class _NameContent extends StatelessWidget {
  final AllahName name;
  const _NameContent({required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.domeGreen.withValues(alpha: 0.5),
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.6)),
            ),
            child: Text('${name.number}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.goldLight)),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(name.arabic,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                    fontSize: 40, height: 1.5, color: AppColors.goldLight)),
          ),
          const SizedBox(height: 8),
          Text(name.translit,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(name.localizedMeaning,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  color: Colors.white.withValues(alpha: 0.8))),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const _NavBar(
      {required this.index,
      required this.total,
      required this.onPrev,
      required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _round(Icons.chevron_left, onPrev),
          Text('${index + 1} / $total',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          _round(Icons.chevron_right, onNext),
        ],
      ),
    );
  }

  Widget _round(IconData icon, VoidCallback? onTap) {
    return PressableScale(
      onTap: onTap ?? () {},
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: GlassCard(
          radius: 24,
          blur: 10,
          darkness: 0.18,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

/// Декоративное золотое кольцо вокруг имени.
class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = Colors.white.withValues(alpha: 0.12),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          colors: [AppColors.gold, AppColors.goldLight, AppColors.gold],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => false;
}
