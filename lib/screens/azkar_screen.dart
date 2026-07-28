import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/azkar_data.dart';
import '../services/azkar_remote.dart';
import '../services/lang.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';

/// Азкары и дуа: утренние/вечерние (аль-муаввизат из Корана), после намаза
/// (тасбих) и поминания. У каждого — счётчик повторов и озвучка.
class AzkarScreen extends StatefulWidget {
  const AzkarScreen({super.key});

  @override
  State<AzkarScreen> createState() => _AzkarScreenState();
}

class _AzkarScreenState extends State<AzkarScreen> {
  // Встроенный набор показываем сразу (он выверен и работает офлайн),
  // категории от устаза подгружаются с сервера и добавляются к нему.
  List<AzkarCategory> _cats = buildAzkarCategories();
  int _cat = 0;
  // Счётчики сессии: ключ 'catIndex:itemIndex'.
  final Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _loadRemote();
  }

  Future<void> _loadRemote() async {
    final extra = await AzkarRemote.fetch();
    debugPrint('AZKAR remote categories: ${extra.length} '
        '(${extra.map((c) => c.title).join(", ")})');
    if (!mounted || extra.isEmpty) return;
    setState(() => _cats = [...buildAzkarCategories(), ...extra]);
  }

  @override
  void dispose() {
    VoiceService.instance.stop();
    super.dispose();
  }

  void _tap(int item, int target) {
    final key = '$_cat:$item';
    final next = (_counts[key] ?? 0) + 1;
    setState(() => _counts[key] = next >= target ? 0 : next);
    if (next >= target) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = _cats[_cat];
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(t('Азкары и дуа')),
        centerTitle: true,
      ),
      body: DomeBackground(
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + 52),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _cats.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => _CatTab(
                    category: _cats[i],
                    active: i == _cat,
                    onTap: () => setState(() => _cat = i),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: cat.items.length,
                  itemBuilder: (context, i) => _AzkarCard(
                    azkar: cat.items[i],
                    id: 'azkar_${_cat}_$i',
                    count: _counts['$_cat:$i'] ?? 0,
                    onTap: () => _tap(i, cat.items[i].count),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatTab extends StatelessWidget {
  final AzkarCategory category;
  final bool active;
  final VoidCallback onTap;
  const _CatTab(
      {required this.category, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? AppColors.domeGreen.withValues(alpha: 0.55)
              : Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: active
                  ? AppColors.gold
                  : Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(category.icon,
                size: 18,
                color: active ? AppColors.cream : Colors.white70),
            const SizedBox(width: 6),
            Text(t(category.title),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? AppColors.cream : Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _AzkarCard extends StatelessWidget {
  final Azkar azkar;
  final String id;
  final int count;
  final VoidCallback onTap;
  const _AzkarCard(
      {required this.azkar,
      required this.id,
      required this.count,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FadeSlideIn(
        child: GlassCard(
          radius: 18,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (azkar.source.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.domeGreen.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.5)),
                      ),
                      child: Text(t(azkar.source),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.goldLight)),
                    ),
                  const Spacer(),
                  ValueListenableBuilder<String?>(
                    valueListenable: VoiceService.instance.speakingId,
                    builder: (context, speaking, _) {
                      final active = speaking == id;
                      return IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => VoiceService.instance
                            .speak(id, azkar.arabic, fallback: azkar.translit),
                        icon: Icon(
                            active
                                ? Icons.stop_circle
                                : Icons.volume_up_rounded,
                            color: AppColors.goldLight),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                azkar.arabic,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontFamily: 'AmiriQuran',
                    fontSize: 24,
                    height: 1.9,
                    color: AppColors.goldLight),
              ),
              if (azkar.translit.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(azkar.translit,
                    style: const TextStyle(
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 6),
              Text(t(azkar.meaning),
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.white.withValues(alpha: 0.8))),
              const SizedBox(height: 14),
              _CounterPill(count: count, target: azkar.count, onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

/// Пилюля-счётчик: тап увеличивает, при достижении цели сбрасывается.
class _CounterPill extends StatelessWidget {
  final int count;
  final int target;
  final VoidCallback onTap;
  const _CounterPill(
      {required this.count, required this.target, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final done = count == 0 && target > 1; // после сброса
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accentGreen.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accentGreen),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.touch_app_outlined,
                size: 18, color: AppColors.cream),
            const SizedBox(width: 8),
            Text(
              target > 1
                  ? '${t('Читать')} · $count / $target'
                  : t('Прочитано'),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (done) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle,
                  size: 18, color: AppColors.accentGreen),
            ],
          ],
        ),
      ),
    );
  }
}
