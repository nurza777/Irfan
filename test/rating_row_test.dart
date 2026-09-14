import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/screens/rating_screen.dart';
import 'package:irfan/services/rating_service.dart';

Widget _wrap(RatingRow row) => MaterialApp(
      home: Scaffold(body: RatingRowTile(row: row)),
    );

RatingRow _row({
  int rank = 5,
  String name = 'Айгерим',
  int points = 320,
  int streak = 4,
  int prayers = 60,
  bool me = false,
}) =>
    RatingRow(
      rank: rank,
      name: name,
      points: points,
      streak: streak,
      prayers: prayers,
      me: me,
    );

void main() {
  testWidgets('строка показывает имя, очки и намазы', (tester) async {
    await tester.pumpWidget(_wrap(_row()));
    expect(find.text('Айгерим'), findsOneWidget);
    expect(find.text('320'), findsOneWidget);
    expect(find.textContaining('60'), findsOneWidget);
  });

  testWidgets('первые три места отмечены медалями, остальные — числом',
      (tester) async {
    for (final (rank, medal) in [(1, '🥇'), (2, '🥈'), (3, '🥉')]) {
      await tester.pumpWidget(_wrap(_row(rank: rank)));
      expect(find.text(medal), findsOneWidget,
          reason: 'у $rank места должна быть медаль');
      expect(find.text('$rank'), findsNothing);
    }
    await tester.pumpWidget(_wrap(_row(rank: 4)));
    expect(find.text('4'), findsOneWidget);
    expect(find.text('🥉'), findsNothing);
  });

  testWidgets('своя строка подписана «вы», чужая — нет', (tester) async {
    await tester.pumpWidget(_wrap(_row(me: true)));
    expect(find.textContaining('вы'), findsOneWidget);

    await tester.pumpWidget(_wrap(_row(me: false)));
    expect(find.text('Айгерим'), findsOneWidget);
    expect(find.textContaining(' · вы'), findsNothing);
  });

  testWidgets('без серии про неё не пишем', (tester) async {
    // Нулевая серия у новичка — не повод занимать строку словом «серия 0».
    await tester.pumpWidget(_wrap(_row(streak: 0)));
    expect(find.textContaining('серия'), findsNothing);

    await tester.pumpWidget(_wrap(_row(streak: 7)));
    expect(find.textContaining('серия'), findsOneWidget);
  });

  testWidgets('длинное имя не ломает строку', (tester) async {
    await tester.pumpWidget(_wrap(_row(name: 'А' * 200)));
    // Обрезка по ширине, а не переполнение: иначе Flutter рисует полосатую
    // ленту поверх таблицы.
    expect(tester.takeException(), isNull);
  });
}
