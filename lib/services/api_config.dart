import 'package:shared_preferences/shared_preferences.dart';

/// Единая точка адреса бэкенда (курсы, новости, эфир, комментарии).
///
/// Раньше адрес был захардкожен в трёх сервисах — теперь только здесь.
/// При переезде на HTTPS/домен менять одну строку [defaultBase] (и, желательно,
/// включить проверку TLS-сертификата — см. аудит).
///
/// Для тестов адрес можно переопределить через prefs-ключ `api_base_url`
/// (историческое имя `live_base_url` тоже поддерживается).
class ApiConfig {
  const ApiConfig._();

  static const defaultBase = 'https://api.irfan.kg';

  static Future<String> base() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('api_base_url') ??
        prefs.getString('live_base_url') ??
        defaultBase;
  }
}
