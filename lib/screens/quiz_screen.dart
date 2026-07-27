import 'dart:math';

import 'package:flutter/material.dart';

import '../services/asmaul_husna.dart';
import '../services/lang.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';

/// Вопрос викторины: текст, варианты и индекс правильного.
class QuizQuestion {
  final String question;
  final List<String> options;
  final int answer;
  const QuizQuestion(this.question, this.options, this.answer);
}

/// Общие вопросы по религии (основы Ислама).
const _generalQuestions = <QuizQuestion>[
  QuizQuestion('Сколько столпов Ислама?', ['5', '4', '6', '7'], 0),
  QuizQuestion('Сколько обязательных намазов в день?',
      ['5', '3', '2', '6'], 0),
  QuizQuestion('В каком месяце мусульмане держат пост?',
      ['Рамадан', 'Шавваль', 'Раджаб', 'Мухаррам'], 0),
  QuizQuestion('Сколько ракаатов в намазе Фаджр (фард)?',
      ['2', '3', '4', '1'], 0),
  QuizQuestion('Как называется первый столп Ислама?',
      ['Шахада', 'Закят', 'Хадж', 'Саум'], 0),
  QuizQuestion('Куда обращаются мусульмане во время намаза?',
      ['Кааба в Мекке', 'Иерусалим', 'Медина', 'На восток'], 0),
  QuizQuestion('Священная книга мусульман — это…',
      ['Коран', 'Таурат', 'Инджиль', 'Забур'], 0),
  QuizQuestion('Сколько прекрасных имён у Аллаха?',
      ['99', '100', '40', '70'], 0),
  QuizQuestion('В каком городе находится Кааба?',
      ['Мекка', 'Медина', 'Каир', 'Стамбул'], 0),
  QuizQuestion('Как называется паломничество в Мекку?',
      ['Хадж', 'Умра', 'Зиярат', 'Хиджра'], 0),
  QuizQuestion('Кто является последним пророком в Исламе?',
      ['Мухаммад ﷺ', 'Иса', 'Муса', 'Ибрахим'], 0),
  QuizQuestion('Обязательная милостыня в Исламе называется…',
      ['Закят', 'Садака', 'Фидья', 'Кафара'], 0),
];

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  static const _count = 10;
  final _rng = Random();
  late List<QuizQuestion> _questions;
  int _current = 0;
  int _score = 0;
  int? _picked;

  @override
  void initState() {
    super.initState();
    _questions = _generate();
  }

  List<QuizQuestion> _generate() {
    final all = <QuizQuestion>[];

    // Некоторые имена делят один транслит (напр. «Аль-Маджид» — №48 и №65).
    // Для вопроса «Что означает имя …?» берём только имена с уникальным
    // транслитом, иначе вопрос неоднозначен.
    final translitCounts = <String, int>{};
    for (final n in asmaulHusna) {
      translitCounts[n.translit] = (translitCounts[n.translit] ?? 0) + 1;
    }

    // Вопросы по именам Аллаха (значение ↔ имя).
    final names = List<AllahName>.from(asmaulHusna)..shuffle(_rng);
    for (final n in names.take(14)) {
      final others =
          asmaulHusna.where((x) => x.number != n.number).toList()
            ..shuffle(_rng);
      final byMeaning =
          _rng.nextBool() && translitCounts[n.translit] == 1;
      if (byMeaning) {
        // Что означает имя? Варианты — значения без повторов.
        final distractors = <String>{};
        for (final x in others) {
          if (x.localizedMeaning != n.localizedMeaning) {
            distractors.add(x.localizedMeaning);
          }
          if (distractors.length == 3) break;
        }
        final q = appLang == Lang.ky
            ? '«${n.translit}» деген ысымдын мааниси кандай?'
            : 'Что означает имя «${n.translit}»?';
        all.add(_shuffled(q, n.localizedMeaning, distractors));
      } else {
        // Какое имя означает…? Варианты — имена без повторов.
        final distractors = <String>{};
        for (final x in others) {
          if (x.translit != n.translit) distractors.add(x.translit);
          if (distractors.length == 3) break;
        }
        final q = appLang == Lang.ky
            ? '«${n.localizedMeaning}» кайсы ысымдын мааниси?'
            : 'Какое имя означает «${n.meaning}»?';
        all.add(_shuffled(q, n.translit, distractors));
      }
    }

    all.addAll(_generalQuestions);
    all.shuffle(_rng);
    return all.take(_count).toList();
  }

  /// Собирает вопрос из правильного ответа и уникальных дистракторов.
  QuizQuestion _shuffled(String q, String correct, Set<String> distractors) {
    final opts = <String>{correct, ...distractors}.toList()..shuffle(_rng);
    return QuizQuestion(q, opts, opts.indexOf(correct));
  }

  void _pick(int i) {
    if (_picked != null) return;
    setState(() {
      _picked = i;
      if (i == _questions[_current].answer) _score++;
    });
  }

  void _next() {
    if (_current + 1 >= _questions.length) {
      setState(() => _current = _questions.length); // финал
    } else {
      setState(() {
        _current++;
        _picked = null;
      });
    }
  }

  void _restart() {
    setState(() {
      _questions = _generate();
      _current = 0;
      _score = 0;
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final finished = _current >= _questions.length;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Text(t('Викторина')),
      ),
      body: DomeBackground(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 56, 20, 20),
            child: finished ? _result() : _question(),
          ),
        ),
      ),
    );
  }

  Widget _question() {
    final q = _questions[_current];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(appLang == Lang.ky ? 'Суроо ${_current + 1} / ${_questions.length}' : 'Вопрос ${_current + 1} из ${_questions.length}',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7))),
            const Spacer(),
            Text('${t('Очки')}: $_score',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.goldLight)),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (_current + 1) / _questions.length,
            minHeight: 6,
            backgroundColor: Colors.black.withValues(alpha: 0.3),
            valueColor:
                const AlwaysStoppedAnimation(AppColors.accentGreen),
          ),
        ),
        const SizedBox(height: 20),
        FadeSlideIn(
          key: ValueKey(_current),
          child: GlassCard(
            radius: 20,
            padding: const EdgeInsets.all(20),
            child: Text(t(q.question),
                style: const TextStyle(
                    fontSize: 20,
                    height: 1.35,
                    fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < q.options.length; i++) ...[
          _option(q, i),
          const SizedBox(height: 10),
        ],
        const Spacer(),
        if (_picked != null)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentGreen,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _next,
              child: Text(
                _current + 1 >= _questions.length
                    ? t('Результат')
                    : t('Следующий вопрос'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }

  Widget _option(QuizQuestion q, int i) {
    final answered = _picked != null;
    final isCorrect = i == q.answer;
    final isPicked = i == _picked;
    Color border = Colors.white.withValues(alpha: 0.15);
    Color bg = Colors.black.withValues(alpha: 0.28);
    IconData? icon;
    if (answered && isCorrect) {
      border = AppColors.accentGreen;
      bg = AppColors.accentGreen.withValues(alpha: 0.22);
      icon = Icons.check_circle;
    } else if (answered && isPicked) {
      border = Colors.redAccent;
      bg = Colors.redAccent.withValues(alpha: 0.18);
      icon = Icons.cancel;
    }
    return PressableScale(
      onTap: () => _pick(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1.4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(t(q.options[i]),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            if (icon != null)
              Icon(icon,
                  size: 22,
                  color: isCorrect ? AppColors.accentGreen : Colors.redAccent),
          ],
        ),
      ),
    );
  }

  Widget _result() {
    final total = _questions.length;
    final pct = total == 0 ? 0 : (_score / total * 100).round();
    final (title, emoji) = switch (pct) {
      >= 90 => (t('Машаллах! Отлично!'), '🌟'),
      >= 60 => (t('Хорошо! Так держать'), '👏'),
      >= 30 => (t('Неплохо, но можно лучше'), '📖'),
      _ => (t('Стоит повторить'), '💪'),
    };
    return Center(
      child: FadeSlideIn(
        child: GlassCard(
          radius: 24,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 54)),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Text('$_score / $total',
                  style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      color: AppColors.goldLight)),
              Text('${t('правильных ответов')} ($pct%)',
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.7))),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentGreen,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _restart,
                  icon: const Icon(Icons.replay, size: 20),
                  label: Text(t('Играть снова'),
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style:
                    TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(t('Выйти')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
