// Проверки URL, полученных с сервера (курсы, эфир, новости). Так как каталог
// приходит с бэкенда, а канал пока по HTTP (подвержен MITM), не доверяем
// произвольным схемам: tel:, mailto:, deep-link в другое приложение,
// file: и т.п. должны игнорироваться.

/// Разрешён ли URL для проигрывания/загрузки внутри приложения
/// (video_player, HLS): только http/https.
bool isSafeMediaUrl(String url) {
  final u = Uri.tryParse(url.trim());
  return u != null &&
      u.hasScheme &&
      (u.scheme == 'http' || u.scheme == 'https') &&
      u.host.isNotEmpty;
}

/// Разрешён ли URL для открытия во внешнем приложении (браузере): только
/// http/https — чтобы серверная ссылка не запускала произвольные схемы.
bool isSafeExternalUrl(String url) => isSafeMediaUrl(url);
