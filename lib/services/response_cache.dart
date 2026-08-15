import 'package:shared_preferences/shared_preferences.dart';

/// Последний удачный ответ сервера — чтобы экран открывался сразу.
///
/// Курсы, реестр устазов и новости лежали только на сервере: каждый заход в
/// раздел означал запрос в Германию по мобильной сети и пустой экран с
/// кружком до ответа (а при плохой связи — до восьмисекундного таймаута).
/// Теперь экран рисуется по сохранённому ответу мгновенно, а сеть обновляет
/// его уже под открытым экраном. Заодно разделы читаются без интернета.
///
/// Хранится в тех же настройках, что и всё остальное: данные маленькие
/// (каталог и новости — десятки килобайт), отдельная база ради них не нужна.
/// Ответы крупнее [maxChars] не сохраняются — настройки на Android живут в
/// памяти целиком, и раздувать их незачем.
class ResponseCache {
  static const _prefix = 'cache_';
  static const maxChars = 256 * 1024;

  static Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$key');
  }

  static Future<void> write(String key, String body) async {
    if (body.length > maxChars) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', body);
    await prefs.setInt(
        '$_prefix${key}_at', DateTime.now().millisecondsSinceEpoch);
  }

  /// Когда ответ был получен. Нужно экранам, которые показывают «данные от
  /// такого-то числа», когда сеть недоступна.
  static Future<DateTime?> savedAt(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('$_prefix${key}_at');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
