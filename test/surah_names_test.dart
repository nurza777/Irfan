import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/lang.dart';
import 'package:irfan/services/settings_service.dart';
import 'package:irfan/services/surah_names.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

/// Названия сур кириллицей, склонение числительных и хранение города.
///
/// Всё это ломается тихо: латинское название вернётся, если кто-то снова
/// возьмёт `quran.getSurahName`, а город, найденный по названию, перестанет
/// восстанавливаться, если из настроек уедут координаты. Ни то, ни другое
/// не уронит приложение — просто человек снова не найдёт свою суру и свой
/// город.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('названия сур', () {
    test('их ровно 114 и все кириллицей', () {
      expect(surahNamesRu.length, quran.totalSurahCount);
      for (var n = 1; n <= quran.totalSurahCount; n++) {
        final name = surahName(n);
        expect(name.trim(), isNotEmpty, reason: 'сура $n без названия');
        expect(RegExp(r'[A-Za-z]').hasMatch(name), isFalse,
            reason: 'в названии суры $n осталась латиница: $name');
        expect(RegExp(r'^[А-ЯЁ]').hasMatch(name), isTrue,
            reason: 'сура $n начинается не с прописной: $name');
      }
    });

    test('названия не повторяются', () {
      expect(surahNamesRu.toSet().length, surahNamesRu.length);
    });

    test('знакомые суры на своих местах', () {
      expect(surahName(1), 'Аль-Фатиха');
      expect(surahName(2), 'Аль-Бакара');
      expect(surahName(36), 'Йа Син');
      expect(surahName(55), 'Ар-Рахман');
      expect(surahName(114), 'Ан-Нас');
    });

    test('латинское написание остаётся доступным поиску', () {
      expect(surahNameLatin(2).toLowerCase(), contains('baqara'));
    });
  });

  group('склонение', () {
    setUp(() => appLang = Lang.ru);
    tearDown(() => appLang = Lang.ru);

    test('русские формы', () {
      expect(plural(1, 'аят', 'аята', 'аятов'), '1 аят');
      expect(plural(2, 'аят', 'аята', 'аятов'), '2 аята');
      expect(plural(5, 'аят', 'аята', 'аятов'), '5 аятов');
      // 11–14 — исключение: «11 аятов», а не «11 аят».
      expect(plural(11, 'аят', 'аята', 'аятов'), '11 аятов');
      expect(plural(21, 'аят', 'аята', 'аятов'), '21 аят');
      expect(plural(112, 'аят', 'аята', 'аятов'), '112 аятов');
      expect(plural(0, 'аят', 'аята', 'аятов'), '0 аятов');
    });

    test('в кыргызском счётное слово не меняется', () {
      appLang = Lang.ky;
      expect(plural(7, 'аят', 'аята', 'аятов'), '7 аят');
      expect(plural(1, 'аят', 'аята', 'аятов'), '1 аят');
    });

    test('в шапке суры больше нет «7 аят»', () {
      expect(verseCountLabel(7), '7 аятов');
      expect(verseCountLabel(3), '3 аята');
    });

    test('счётчики курсов и уроков', () {
      expect(plural(5, 'курс', 'курса', 'курсов'), '5 курсов');
      expect(plural(36, 'урок', 'урока', 'уроков'), '36 уроков');
      expect(plural(1, 'урок', 'урока', 'уроков'), '1 урок');
    });
  });

  group('род говорящего', () {
    setUp(() => appLang = Lang.ru);
    tearDown(() => appLang = Lang.ru);

    test('вместо «прочитал(а)» — по полу из профиля', () {
      expect(gendered('Да, прочитал(а)', 'Да, прочитал', 'Да, прочитала', false),
          'Да, прочитал');
      expect(gendered('Да, прочитал(а)', 'Да, прочитал', 'Да, прочитала', true),
          'Да, прочитала');
    });

    test('в кыргызском рода у глагола нет — берётся перевод', () {
      appLang = Lang.ky;
      final m = gendered('Пропустил(а)', 'Пропустил', 'Пропустила', false);
      final f = gendered('Пропустил(а)', 'Пропустила', 'Пропустила', true);
      expect(m, f);
      expect(m, isNot(contains('(')));
    });
  });

  group('выбранный город', () {
    test('запись прежних сборок — просто имя — читается', () async {
      SharedPreferences.setMockInitialValues({'flutter.settings_city': 'Ош'});
      final s = await SettingsService.create();
      expect(s.manualCity.name, 'Ош');
      expect(s.manualCity.lat, closeTo(40.52, 0.1));
    });

    test('найденный по названию город переживает перезапуск', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await SettingsService.create();
      await s.setManualCity(const City('Кызыл-Кия', 40.2569, 72.13));
      final again = await SettingsService.create();
      expect(again.manualCity.name, 'Кызыл-Кия');
      expect(again.manualCity.lat, closeTo(40.2569, 0.0001));
      expect(again.manualCity.lon, closeTo(72.13, 0.0001));
    });

    test('испорченная запись не оставляет без времени намаза', () async {
      SharedPreferences.setMockInitialValues(
          {'flutter.settings_city': '{"name":"Ош"'});
      final s = await SettingsService.create();
      expect(s.manualCity.name, SettingsService.cities.first.name);
    });

    test('в списке нет повторов и пустых координат', () {
      final names = SettingsService.cities.map((c) => c.name).toList();
      expect(names.toSet().length, names.length);
      for (final c in SettingsService.cities) {
        expect(c.lat, isNot(0));
        expect(c.lon, isNot(0));
        expect(c.lat.abs() <= 90 && c.lon.abs() <= 180, isTrue,
            reason: '${c.name}: координаты за пределами карты');
      }
    });
  });
}
