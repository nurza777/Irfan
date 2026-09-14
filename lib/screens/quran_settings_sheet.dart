
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/quran_audio_cache.dart';
import '../services/quran_service.dart';
import '../services/quran_translations.dart';
import '../services/reciters.dart';
import '../services/lang.dart';
import '../theme.dart';
import '../widgets/glass.dart';

/// Настройки чтения Корана: режим, отображение (арабский/перевод/таджвид),
/// размер шрифта, чтец, перевод. Открывается на половину экрана, фиксируется
/// там и тянется вверх/вниз (DraggableScrollableSheet).
Future<void> showQuranSettings(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _QuranSettings(),
  );
}

class _QuranSettings extends StatelessWidget {
  const _QuranSettings();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final qs = state.quran!;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.5],
      expand: false,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          child: MaybeBlur(
            child: Container(
              color: AppColors.skyBottom.withValues(alpha: sheetAlpha(0.9)),
              child: AnimatedBuilder(
                animation: qs,
                builder: (context, _) {
                  final display = qs.display;
                  return ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(20, 12, 20,
                        24 + MediaQuery.of(context).padding.bottom),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(t('Настройки чтения'),
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      _label(t('РЕЖИМ ЧТЕНИЯ')),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final m in ReadingMode.values) ...[
                            Expanded(
                              child: _ModeCard(
                                mode: m,
                                active: qs.mode == m,
                                onTap: () => qs.setMode(m),
                              ),
                            ),
                            if (m != ReadingMode.values.last)
                              const SizedBox(width: 10),
                          ],
                        ],
                      ),
                      const SizedBox(height: 18),
                      _label(t('ОТОБРАЖЕНИЕ')),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _toggle(t('Арабский'), display.arabic,
                              (v) => qs.setDisplay(display.copyWith(arabic: v))),
                          _toggle(t('Перевод'), display.translation,
                              (v) => qs.setDisplay(
                                  display.copyWith(translation: v))),
                          _toggle(t('Правила таджвида'), display.tajwid,
                              (v) => qs.setDisplay(display.copyWith(tajwid: v))),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _label(t('РАЗМЕР АРАБСКОГО ШРИФТА')),
                      Row(
                        children: [
                          const Text('ا',
                              style: TextStyle(fontSize: 16)),
                          Expanded(
                            child: Slider(
                              value: qs.arabicFontSize,
                              min: 20,
                              max: 40,
                              divisions: 10,
                              activeColor: AppColors.gold,
                              label: qs.arabicFontSize.round().toString(),
                              onChanged: (v) => qs.setArabicFontSize(v),
                            ),
                          ),
                          const Text('ا',
                              style: TextStyle(fontSize: 30)),
                        ],
                      ),
                      // Выбора шрифта больше нет — он один, «Мусхаф».
                      const SizedBox(height: 18),
                      _label(t('ЧТЕЦ')),
                      const SizedBox(height: 8),
                      for (final r in quranReciters)
                        _ReciterTile(
                          reciter: r,
                          active: qs.reciter.id == r.id,
                          onTap: () => qs.setReciter(r),
                        ),
                      const SizedBox(height: 18),
                      _label(t('ПЕРЕВОД')),
                      const SizedBox(height: 8),
                      // Когда перевод один, список из одной строки — это
                      // выбор без выбора. Показываем, чей текст читает
                      // человек: указание источника всё равно обязательно.
                      if (quranTranslations.length == 1)
                        _TranslationSource(quranTranslations.first)
                      else
                        for (final t in quranTranslations)
                          _TranslationTile(
                            translation: t,
                            active: qs.translation.id == t.id,
                            onTap: () => qs.setTranslation(t),
                          ),
                      const SizedBox(height: 18),
                      _label(t('ОФФЛАЙН-АУДИО')),
                      const SizedBox(height: 8),
                      const _OfflineAudioCard(),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _label(String t) => Text(t,
      style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: Colors.white.withValues(alpha: 0.5)));

  Widget _toggle(String text, bool active, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!active),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accentGreen.withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: active
                  ? AppColors.accentGreen
                  : Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: active
                    ? AppColors.accentGreen
                    : Colors.white.withValues(alpha: 0.5)),
            const SizedBox(width: 6),
            Text(text,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }

}

/// Строка выбора перевода: имя + пояснение (язык/стиль), радио и галочка.
/// Единственный перевод — не переключатель, а строка «чей текст вы читаете».
class _TranslationSource extends StatelessWidget {
  final QuranTranslation translation;
  const _TranslationSource(this.translation);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.translate,
              size: 20, color: AppColors.goldLight),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(translation.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${translation.subtitle} · ${t('с разрешения источника')}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TranslationTile extends StatelessWidget {
  final QuranTranslation translation;
  final bool active;
  final VoidCallback onTap;
  const _TranslationTile(
      {required this.translation,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? AppColors.gold.withValues(alpha: 0.16)
              : Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: active
                  ? AppColors.gold
                  : Colors.white.withValues(alpha: 0.12),
              width: active ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(
                active
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: active
                    ? AppColors.goldLight
                    : Colors.white.withValues(alpha: 0.45)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(translation.name,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? AppColors.cream : Colors.white)),
                  Text(t(translation.subtitle),
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.55))),
                ],
              ),
            ),
            if (active)
              const Icon(Icons.check, size: 18, color: AppColors.goldLight),
          ],
        ),
      ),
    );
  }
}

/// Строка выбора чтеца: радио-кружок, имя, галочка у активного.
class _ReciterTile extends StatelessWidget {
  final QuranReciter reciter;
  final bool active;
  final VoidCallback onTap;
  const _ReciterTile(
      {required this.reciter, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active
              ? AppColors.gold.withValues(alpha: 0.16)
              : Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: active
                  ? AppColors.gold
                  : Colors.white.withValues(alpha: 0.12),
              width: active ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(
                active
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: active
                    ? AppColors.goldLight
                    : Colors.white.withValues(alpha: 0.45)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(reciter.name,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? AppColors.cream : Colors.white)),
            ),
            if (active)
              const Icon(Icons.check, size: 18, color: AppColors.goldLight),
          ],
        ),
      ),
    );
  }
}
class _ModeCard extends StatelessWidget {
  final ReadingMode mode;
  final bool active;
  final VoidCallback onTap;
  const _ModeCard(
      {required this.mode, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: active ? 0.4 : 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: active
                  ? AppColors.gold
                  : Colors.white.withValues(alpha: 0.15),
              width: active ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Icon(
                mode == ReadingMode.sura
                    ? Icons.article_outlined
                    : Icons.menu_book,
                color: active ? AppColors.goldLight : Colors.white,
                size: 26),
            const SizedBox(height: 6),
            Text(t(mode.titleRu),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        active ? FontWeight.w700 : FontWeight.w500)),
            const SizedBox(height: 2),
            Text(t(mode.subtitleRu),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }
}

/// Сколько занято оффлайн-аудио и кнопка всё удалить.
class _OfflineAudioCard extends StatefulWidget {
  const _OfflineAudioCard();

  @override
  State<_OfflineAudioCard> createState() => _OfflineAudioCardState();
}

class _OfflineAudioCardState extends State<_OfflineAudioCard> {
  int _bytes = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    QuranAudioCache.instance.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    QuranAudioCache.instance.revision.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final v = await QuranAudioCache.instance.totalSize();
    if (mounted) setState(() => _bytes = v);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.download_done,
              color: AppColors.goldLight, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('Скачанные суры играют без интернета'),
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Text('${t('Занято на устройстве')}: ${formatBytes(_bytes)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6))),
              ],
            ),
          ),
          if (_bytes > 0)
            IconButton(
              tooltip: t('Удалить всё скачанное аудио'),
              onPressed: () async {
                await QuranAudioCache.instance.deleteAll();
              },
              icon: const Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 20),
            ),
        ],
      ),
    );
  }
}
