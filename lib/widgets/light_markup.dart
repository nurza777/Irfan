import 'package:flutter/material.dart';

/// Отрисовка маленького подмножества разметки, в котором хранится тафсир.
///
/// Поддерживается ровно то, что встречается в исходном тексте:
///
///     **полужирный**   *курсив*   - пункт списка   > цитата   ### заголовок
///
/// Абзацы разделяются пустой строкой. Своя отрисовка вместо `flutter_html`
/// намеренно: пакет тянет за собой парсер HTML и половину движка вёрстки
/// ради шести правил, а тут своих правил всего шесть — тем же соображением
/// в проекте сделан свой сбор сбоев вместо Sentry.
///
/// К непарным `**` устойчива: в исходных текстах таких мест полтора десятка
/// на четыре с лишним тысячи, и ронять из-за них абзац нельзя — лишний
/// маркер просто показывается как есть.
class LightMarkup extends StatelessWidget {
  final String text;
  final TextStyle style;

  const LightMarkup(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      if (line.startsWith('### ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(line.substring(4).trim(),
              style: style.copyWith(
                  fontSize: style.fontSize! + 2,
                  fontWeight: FontWeight.w700,
                  height: 1.35)),
        ));
      } else if (line.startsWith('> ')) {
        blocks.add(Container(
          margin: const EdgeInsets.only(top: 8, bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          decoration: BoxDecoration(
            // Цитата из классиков — та часть, ради которой тафсир и читают;
            // она должна быть видна глазом, а не теряться в потоке.
            border: const Border(
                left: BorderSide(color: Color(0xFFD4AF61), width: 3)),
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: const BorderRadius.only(
                topRight: Radius.circular(8),
                bottomRight: Radius.circular(8)),
          ),
          child: _rich(line.substring(2), style.copyWith(
              fontStyle: FontStyle.italic,
              color: style.color?.withValues(alpha: 0.92))),
        ));
      } else if (line.startsWith('- ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Text('•', style: style),
              ),
              Expanded(child: _rich(line.substring(2), style)),
            ],
          ),
        ));
      } else {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: _rich(line, style),
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  /// Разбирает `**жирный**` и `*курсив*` в одну строку текста.
  Widget _rich(String line, TextStyle base) =>
      Text.rich(TextSpan(children: _spans(line, base)), softWrap: true);

  static List<TextSpan> _spans(String line, TextStyle base) {
    final out = <TextSpan>[];
    final buf = StringBuffer();
    var bold = false, italic = false;

    void flush() {
      if (buf.isEmpty) return;
      out.add(TextSpan(
        text: buf.toString(),
        style: base.copyWith(
          fontWeight: bold ? FontWeight.w700 : base.fontWeight,
          fontStyle: italic ? FontStyle.italic : base.fontStyle,
        ),
      ));
      buf.clear();
    }

    var i = 0;
    while (i < line.length) {
      final two = i + 1 < line.length ? line.substring(i, i + 2) : '';
      if (two == '**') {
        // Открывающий маркер без закрывающего оставляем текстом: иначе
        // остаток абзаца молча уехал бы в полужирный.
        if (bold || line.indexOf('**', i + 2) >= 0) {
          flush();
          bold = !bold;
          i += 2;
          continue;
        }
      } else if (line[i] == '*') {
        if (italic || line.indexOf('*', i + 1) >= 0) {
          flush();
          italic = !italic;
          i += 1;
          continue;
        }
      }
      buf.write(line[i]);
      i++;
    }
    flush();
    return out.isEmpty ? [TextSpan(text: line, style: base)] : out;
  }
}
