import 'package:flutter/material.dart';

/// Правило таджвида: цвет подсветки, название и пояснение.
enum TajwidRule {
  madd(
    'Мад',
    Color(0xFFE5484D),
    'Красным отмечено удлинение (мад): буквы протяжения ا و ي и знак мада ٓ '
    'читаются дольше — на 2, 4 или 6 счётов.',
  ),
  tafkhim(
    'Тафхим',
    Color(0xFF2F6BFF),
    'Тёмно-синим отмечены «тяжёлые» буквы خ ص ض غ ط ق ظ (и ر в ряде случаев). '
    'Произносятся твёрдо, с поднятием корня языка.',
  ),
  qalqala(
    'Калькаля',
    Color(0xFF37C3E0),
    'Голубым отмечена калькаля — буквы ق ط ب ج د с сукуном произносятся '
    'с лёгким «отскоком» (вибрацией) в точке артикуляции.',
  ),
  ghunna(
    'Гунна / Ихфа',
    Color(0xFF2FA86C),
    'Зелёным отмечена гунна — носовой призвук на ن и م с шаддой (ّ), '
    'а также при слиянии/сокрытии (ихфа). Тянется около 2 счётов.',
  ),
  silent(
    'Тихие буквы',
    Color(0xFF9AA0A6),
    'Серым отмечены буквы, которые не произносятся (например, соединительная '
    'хамза или «немой» алиф).',
  );

  final String titleRu;
  final Color color;
  final String description;
  const TajwidRule(this.titleRu, this.color, this.description);
}

/// Упрощённая подсветка таджвида по буквам — как ориентир для чтения.
/// Не заменяет обучение у устаза, но помогает видеть основные правила.
class Tajwid {
  static const _tafkhim = {'خ', 'ص', 'ض', 'غ', 'ط', 'ق', 'ظ'};
  static const _qalqala = {'ق', 'ط', 'ب', 'ج', 'د'};

  // Диакритика.
  static const _shadda = 'ّ';
  static const _sukun = 'ْ';
  static const _maddSign = 'ٓ';
  static const _daggerAlef = 'ٰ';

  static bool _isMark(int code) =>
      (code >= 0x064B && code <= 0x065F) ||
      code == 0x0670 ||
      (code >= 0x06D6 && code <= 0x06ED);

  /// Разбивает текст аята на цветные фрагменты по правилам таджвида.
  static List<TextSpan> spans(String text, TextStyle base) {
    final spans = <TextSpan>[];
    var i = 0;
    final n = text.length;

    while (i < n) {
      // Собираем «кластер»: базовый символ + прикреплённые к нему знаки.
      final start = i;
      final baseChar = text[i];
      i++;
      final marks = StringBuffer();
      while (i < n && _isMark(text.codeUnitAt(i))) {
        marks.write(text[i]);
        i++;
      }
      final cluster = text.substring(start, i);
      final m = marks.toString();

      final rule = _classify(baseChar, m);
      spans.add(TextSpan(
        text: cluster,
        style: rule == null ? base : base.copyWith(color: rule.color),
      ));
    }
    return spans;
  }

  static TajwidRule? _classify(String base, String marks) {
    // Мад: знак мада, кинжальный алиф или буквы протяжения с мадом.
    if (marks.contains(_maddSign) ||
        marks.contains(_daggerAlef) ||
        base == 'آ' /* آ */) {
      return TajwidRule.madd;
    }
    // Гунна: нун/мим с шаддой.
    if ((base == 'ن' /* ن */ || base == 'م' /* م */) &&
        marks.contains(_shadda)) {
      return TajwidRule.ghunna;
    }
    // Калькаля: буквы ق ط ب ج د с сукуном.
    if (_qalqala.contains(base) && marks.contains(_sukun)) {
      return TajwidRule.qalqala;
    }
    // Тафхим: «тяжёлые» буквы.
    if (_tafkhim.contains(base)) {
      return TajwidRule.tafkhim;
    }
    return null;
  }
}
