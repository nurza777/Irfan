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

  /// Список всех имён с поиском.
  ///
  /// Без него до 77-го имени надо было свайпнуть 76 раз: PageView — хороший
  /// способ читать подряд и негодный, чтобы найти нужное.
  Future<void> _openIndex() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _NamesIndexSheet(),
    );
    if (picked == null || !mounted) return;
    VoiceService.instance.stop();
    // jumpToPage, а не animateToPage: пролистывать 90 страниц анимацией —
    // это несколько секунд мелькания.
    _controller.jumpToPage(picked);
    setState(() => _index = picked);
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
          IconButton(
            tooltip: t('Все имена'),
            onPressed: _openIndex,
            icon: const Icon(Icons.format_list_numbered,
                color: AppColors.goldLight),
          ),
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


/// Лист «все имена»: поиск по номеру, имени и значению.
class _NamesIndexSheet extends StatefulWidget {
  const _NamesIndexSheet();

  @override
  State<_NamesIndexSheet> createState() => _NamesIndexSheetState();
}

class _NamesIndexSheetState extends State<_NamesIndexSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Сравниваем без диакритики и дефисов: человек набирает «аль азиз»,
  /// а в данных «Аль-‘Азиз» — иначе поиск молчал бы на верном запросе.
  String _fold(String v) => v
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r"[^а-яёa-z0-9]"), '');

  List<int> get _found {
    final q = _fold(_query.text);
    if (q.isEmpty) return [for (var i = 0; i < asmaulHusna.length; i++) i];
    return [
      for (var i = 0; i < asmaulHusna.length; i++)
        if ('${asmaulHusna[i].number}' == q ||
            _fold(asmaulHusna[i].translit).contains(q) ||
            _fold(asmaulHusna[i].localizedMeaning).contains(q) ||
            _fold(asmaulHusna[i].meaning).contains(q))
          i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: GlassSheet(
        opacity: 0.86,
        material: true,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: TextField(
                    controller: _query,
                    autofocus: false,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search,
                          size: 20, color: AppColors.gold),
                      hintText: t('Имя, значение или номер'),
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45)),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.28),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.gold),
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: found.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                          child: Text(t('Ничего не найдено'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.7))),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: found.length,
                          itemBuilder: (context, k) {
                            final i = found[k];
                            final n = asmaulHusna[i];
                            return ListTile(
                              dense: true,
                              leading: SizedBox(
                                width: 34,
                                child: Text('${n.number}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.goldLight
                                            .withValues(alpha: 0.85))),
                              ),
                              title: Text(n.translit,
                                  style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(n.localizedMeaning,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white
                                          .withValues(alpha: 0.65))),
                              trailing: Text(n.arabic,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontFamily: 'AmiriQuran',
                                      color: AppColors.cream)),
                              onTap: () => Navigator.pop(context, i),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
