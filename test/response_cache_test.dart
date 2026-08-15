import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:irfan/services/courses_service.dart';
import 'package:irfan/services/news_service.dart';
import 'package:irfan/services/response_cache.dart';

/// Сохранённый ответ сервера — то, что рисуется в разделе до прихода сети.
/// Если он перестанет читаться, экраны молча вернутся к пустому кружку на
/// каждый заход, поэтому разбор сохранённого закреплён тестами.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('записанный ответ читается обратно вместе с датой', () async {
    await ResponseCache.write('пример', '{"a":1}');

    expect(await ResponseCache.read('пример'), '{"a":1}');
    final at = await ResponseCache.savedAt('пример');
    expect(at, isNotNull);
    expect(DateTime.now().difference(at!).inMinutes, 0);
  });

  test('чего не сохраняли — того и нет', () async {
    expect(await ResponseCache.read('пусто'), isNull);
    expect(await ResponseCache.savedAt('пусто'), isNull);
  });

  test('слишком длинный ответ не сохраняется', () async {
    await ResponseCache.write('толстый', 'я' * (ResponseCache.maxChars + 1));
    expect(await ResponseCache.read('толстый'), isNull);
  });

  test('каталог курсов поднимается из сохранённого', () async {
    await ResponseCache.write(CoursesService.cacheKey, '''
{"updated":"2026-08-15","teachers":[
  {"id":"t1","name":"Фархат Устаз","bio":"","directions":[
    {"title":"Таджвид","courses":[
      {"title":"Основы","lessons":[{"title":"Урок 1","url":"http://e/1.mp4"}]}
    ]}
  ]}
]}''');

    final catalog = await CoursesService.cached();
    expect(catalog, isNotNull);
    expect(catalog!.teachers.single.name, 'Фархат Устаз');
    expect(catalog.teachers.single.directions.single.title, 'Таджвид');
  });

  test('битое сохранённое не роняет экран, а считается отсутствующим',
      () async {
    await ResponseCache.write(CoursesService.cacheKey, 'не json вовсе');
    expect(await CoursesService.cached(), isNull);

    await ResponseCache.write(NewsService.cacheKey, '{{{');
    expect(await NewsService.cached(), isNull);
  });

  test('лента новостей поднимается из сохранённого и идёт новыми сверху',
      () async {
    await ResponseCache.write(NewsService.cacheKey, '''
{"items":[
  {"title":"Старая","body":"текст","date":"2026-08-01T10:00:00"},
  {"title":"Свежая","body":"текст","date":"2026-08-14T10:00:00"}
]}''');

    final items = await NewsService.cached();
    expect(items, isNotNull);
    expect(items!.map((n) => n.title), ['Свежая', 'Старая']);
  });
}
