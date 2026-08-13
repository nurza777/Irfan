import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/lang.dart';
import '../services/tafsir_service.dart';
import '../theme.dart';
import '../widgets/light_markup.dart';

/// Показывает толкование аята листом снизу.
///
/// Тексты — с azan.ru, с разрешения правообладателя. Указание источника
/// стоит под каждым толкованием и убирать его нельзя: это условие, на
/// котором материалы разрешено использовать.
Future<void> showTafsir(BuildContext context, int surah, int verse) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TafsirSheet(surah: surah, verse: verse),
  );
}

class _TafsirSheet extends StatelessWidget {
  final int surah;
  final int verse;
  const _TafsirSheet({required this.surah, required this.verse});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12211F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: FutureBuilder<TafsirEntry?>(
          future: TafsirService.instance.forVerse(surah, verse),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _body(context, controller, snap.data);
          },
        ),
      ),
    );
  }

  Widget _body(
      BuildContext context, ScrollController controller, TafsirEntry? e) {
    final text = TextStyle(
        fontSize: 15.5,
        height: 1.55,
        color: Colors.white.withValues(alpha: 0.9));
    final muted =
        TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55));

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Row(
          children: [
            const Icon(Icons.menu_book_outlined,
                color: AppColors.goldLight, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t('Тафсир'),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 20),
            ),
          ],
        ),
        if (e != null && e.hasText && e.rangeLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              // Толкование у azan.ru групповое: один текст объясняет
              // несколько аятов. Об этом надо сказать прямо, иначе человек
              // решит, что открыл не тот аят.
              e.from == e.to
                  ? '${t('Сура')} $surah, ${e.rangeLabel}'
                  : '${t('Сура')} $surah, ${e.rangeLabel} — '
                      '${t('общее толкование')}',
              style: muted,
            ),
          ),
        const SizedBox(height: 10),
        if (e == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Text(t('Для этого аята толкования пока нет.'),
                textAlign: TextAlign.center, style: text),
          )
        else ...[
          if (e.hasText) LightMarkup(e.text, style: text),
          if (!e.hasText && e.intro.isNotEmpty) ...[
            Text(t('К самому аяту толкования нет — вот что сказано о суре:'),
                style: muted),
            const SizedBox(height: 10),
            LightMarkup(e.intro, style: text),
          ],
          if (e.hasText && e.intro.isNotEmpty) ...[
            const SizedBox(height: 18),
            _AboutSura(intro: e.intro, style: text),
          ],
          const SizedBox(height: 22),
          const Divider(color: Colors.white12),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${t('Источник')}: Azan.ru · '
                  '${t('выгрузка от')} ${TafsirService.snapshotDate}',
                  style: muted,
                ),
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(e.sourceUrl),
                    mode: LaunchMode.externalApplication),
                child: Text(t('Открыть')),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Вступление к суре — под свёрткой: оно длинное и повторяется у каждого
/// аята суры, а нужно не всегда.
class _AboutSura extends StatefulWidget {
  final String intro;
  final TextStyle style;
  const _AboutSura({required this.intro, required this.style});

  @override
  State<_AboutSura> createState() => _AboutSuraState();
}

class _AboutSuraState extends State<_AboutSura> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: AppColors.goldLight),
                const SizedBox(width: 6),
                Text(t('О суре'),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.goldLight)),
              ],
            ),
          ),
        ),
        if (_open) LightMarkup(widget.intro, style: widget.style),
      ],
    );
  }
}
