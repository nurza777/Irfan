import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Где ученик остановился в каждом уроке.
///
/// Хранится локально: сервер о просмотре не знает, а урок человек смотрит
/// с одного телефона. Ключ — сам URL видео: своих id у уроков нет, а ссылка
/// в каталоге и есть то, что отличает урок от урока.
class WatchProgress extends ChangeNotifier {
  WatchProgress._();
  static final WatchProgress instance = WatchProgress._();

  static const _prefix = 'lesson_at_';

  SharedPreferences? _p;
  bool _loading = false;

  /// Урок считается просмотренным, когда доиграл почти до конца: последние
  /// секунды — обычно прощание и заставка, из-за них никто не вернётся.
  static const _doneFraction = 0.97;

  /// Меньше этого к позиции не возвращаемся — «продолжить с 3-й секунды»
  /// выглядит как сбой, а не как забота.
  static const minResumeSeconds = 15;

  Future<void> init() async {
    if (_p != null || _loading) return;
    _loading = true;
    _p = await SharedPreferences.getInstance();
    _loading = false;
    notifyListeners();
  }

  String _key(String url) => '$_prefix${url.hashCode}';

  /// Позиция и длительность в секундах; обе 0, если урок ещё не открывали.
  (int, int) _read(String url) {
    final raw = _p?.getString(_key(url));
    if (raw == null) return (0, 0);
    final parts = raw.split('|');
    if (parts.length != 2) return (0, 0);
    return (int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
  }

  /// С какой секунды продолжить. 0 — начинать сначала.
  int resumeAt(String url) {
    final (pos, dur) = _read(url);
    if (pos < minResumeSeconds) return 0;
    // Досмотренный урок открываем с начала: скорее всего его пересматривают.
    if (dur > 0 && pos >= dur * _doneFraction) return 0;
    return pos;
  }

  bool isDone(String url) {
    final (pos, dur) = _read(url);
    return dur > 0 && pos >= dur * _doneFraction;
  }

  /// Доля просмотренного (0..1) для полоски в списке уроков.
  double fraction(String url) {
    final (pos, dur) = _read(url);
    if (dur <= 0) return 0;
    if (isDone(url)) return 1;
    return (pos / dur).clamp(0.0, 1.0);
  }

  bool started(String url) => _read(url).$1 >= minResumeSeconds;

  Future<void> save(String url, Duration position, Duration duration) async {
    final p = _p;
    if (p == null || duration.inSeconds <= 0) return;
    final pos = position.inSeconds.clamp(0, duration.inSeconds);
    final (oldPos, oldDur) = _read(url);
    if (pos == oldPos && duration.inSeconds == oldDur) return;
    await p.setString(_key(url), '$pos|${duration.inSeconds}');
    notifyListeners();
  }

  Future<void> reset(String url) async {
    await _p?.remove(_key(url));
    notifyListeners();
  }
}
