import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/auth_service.dart';
import '../services/certificate_service.dart';
import '../services/date_fmt.dart';
import '../services/lang.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import '../widgets/support_card.dart';
import 'restore_account_screen.dart';
import 'settings_screen.dart';
import 'certificates_screen.dart';
import 'rating_screen.dart';
import 'shop_screen.dart';
import 'zikr_settings_sheet.dart';

/// Личный кабинет: без входа — форма регистрации/авторизации,
/// после входа — профиль со статистикой намазов и зикров.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final user = state.auth!.current;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(user == null ? t('Аккаунт') : t('Личный кабинет')),
        centerTitle: true,
      ),
      body: DomeBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 66, 20, 24),
            child:
                user == null ? const _AuthForm() : _Profile(user: user),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Вход

/// «25 лет» / «21 год» / «22 года». Нужна и в форме регистрации, и в карточке
/// профиля — поэтому вынесена из класса, а не скопирована во второй раз.
String _years(int n) {
  if (appLang == Lang.ky) return '$n жаш';
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return '$n год';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n года';
  return '$n лет';
}

/// Полных лет от даты рождения до сегодня.
int ageFromBirth(DateTime b) {
  final now = DateTime.now();
  var y = now.year - b.year;
  if (now.month < b.month || (now.month == b.month && now.day < b.day)) y--;
  return y;
}

class _AuthForm extends StatefulWidget {
  const _AuthForm();

  @override
  State<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<_AuthForm> {
  bool _isLogin = true;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  Gender? _gender;
  final _name = TextEditingController();
  /// Дата рождения вместо числа лет: число застывало навсегда — анкета
  /// говорила «25» и через три года.
  DateTime? _birth;
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = AppScope.of(context);
    final err = _isLogin
        ? await state.loginAccount(
            phone: _phone.text, password: _password.text)
        : await state.registerAccount(
            name: _name.text,
            phone: _phone.text,
            password: _password.text,
            birthDate: _birth,
            gender: _gender,
            city: _city.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    // Успешная регистрация — сначала прямо об этом говорим.
    //
    // Раньше экран просто сменялся на подтверждение номера, и человек не
    // понимал, завелась ли учётная запись: подтверждение номера выглядит
    // как продолжение анкеты, а не как «готово».
    if (err == null && !_isLogin && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('Регистрация прошла успешно')),
        backgroundColor: AppColors.accentGreen,
        duration: const Duration(seconds: 3),
      ));
    }
    // Кода подтверждения в приложении БОЛЬШЕ НЕТ НИГДЕ — ни после анкеты,
    // ни при переезде на новый телефон.
    //
    // Автоотправка не подключена: код называл устаз вручную, и человек
    // упирался в ожидание на ровном месте. По решению владельца люди входят
    // своим номером и паролем, и этого достаточно.
    //
    // Доказательством «номер мой» теперь служит пароль: приложение считает
    // из него значение, одинаковое на любом телефоне, и сервер сверяет его
    // со своим (см. AuthService.makeProof). Забыл пароль — админ сбрасывает
    // его в панели.
  }

  Future<void> _restore() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const RestoreAccountScreen()),
    );
    if (ok == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Column(
      children: [
        const SizedBox(height: 10),
        FadeSlideIn(
          child: GlassCard(
            radius: 26,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    _tab(t('Вход'), _isLogin, () {
                      setState(() {
                        _isLogin = true;
                        _error = null;
                      });
                    }),
                    const SizedBox(width: 10),
                    _tab(t('Регистрация'), !_isLogin, () {
                      setState(() {
                        _isLogin = false;
                        _error = null;
                      });
                    }),
                  ],
                ),
                const SizedBox(height: 18),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  child: _isLogin
                      ? const SizedBox.shrink()
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextField(
                                controller: _name,
                                textCapitalization:
                                    TextCapitalization.words,
                                decoration:
                                    _dec('Имя', Icons.person_outline),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _birthField(),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextField(
                                controller: _city,
                                textCapitalization:
                                    TextCapitalization.words,
                                decoration: _dec(
                                    'Город', Icons.location_city_outlined),
                              ),
                            ),
                            // Язык — первым: человек, которому удобнее
                            // кыргызский, должен переключиться до того, как
                            // начнёт разбирать анкету, а не после.
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 4, bottom: 6),
                              child: Text(t('Язык'),
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white
                                          .withValues(alpha: 0.55))),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Row(
                                children: [
                                  for (final l in Lang.values) ...[
                                    Expanded(
                                      child: _langTab(l,
                                          state.settings?.lang == l,
                                          () => state.setLanguage(l)),
                                    ),
                                    if (l != Lang.values.last)
                                      const SizedBox(width: 10),
                                  ],
                                ],
                              ),
                            ),
                            // Пол — необязателен, и это написано прямо на
                            // экране. Нужен он ровно для окончаний в
                            // поздравлениях и на дипломе; не указан — пишем
                            // в мужском роде. Обязательным он быть не может:
                            // App Store запрещает требовать личные данные,
                            // без которых приложение работает (5.1.1(v)).
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 4, bottom: 6),
                              child: Text(
                                  t('Пол (необязательно)'),
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white
                                          .withValues(alpha: 0.55))),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  for (final g in Gender.values) ...[
                                    Expanded(child: _genderTab(g)),
                                    if (g != Gender.values.last)
                                      const SizedBox(width: 10),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  autocorrect: false,
                  decoration: _dec('Телефон', Icons.phone_outlined)
                      .copyWith(hintText: '+996 555 12 34 56'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration:
                      _dec('Пароль', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                      icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color:
                              Colors.white.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  child: _error == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            children: [
                              Text(_error!,
                                  style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 14)),
                              // Восстановление пароля — через админа: он
                              // сбрасывает пароль в панели, и следующий вход
                              // задаёт новый. Кнопки связи показываем прямо
                              // под ошибкой, чтобы не искать их в настройках.
                              if (_isLogin && _error == t('Неверный пароль'))
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: SupportCard(
                                    text: t('Забыли пароль? Свяжитесь с нами — '
                                        'сбросим его, и вы войдёте с новым.'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      // Главное действие — золотое, как остальные акценты;
                      // плоский зелёный прямоугольник выпадал из палитры.
                      backgroundColor: AppColors.gold,
                      foregroundColor: const Color(0xFF20180A),
                      disabledBackgroundColor:
                          AppColors.gold.withValues(alpha: 0.4),
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF20180A)))
                        : Text(
                            _isLogin ? t('Войти') : t('Создать аккаунт'),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                  ),
                ),
                // Отдельная кнопка осталась, хотя обычный «Войти» теперь
                // и сам сходит на сервер, если записи на телефоне нет.
                // Человек, у которого аккаунт «пропал» вместе со старым
                // аппаратом, ищет глазами именно слово «восстановить» — и
                // этот экран ещё показывает, что именно вернётся.
                if (_isLogin)
                  TextButton(
                    onPressed: _busy ? null : _restore,
                    child: Text(t('Новый телефон? Восстановить аккаунт'),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 13)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        FadeSlideIn(
          delay: const Duration(milliseconds: 200),
          // Подпись ложится прямо на фото подсвеченных зданий — без подложки
          // серый текст на них не читался.
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              t('Аккаунт хранится локально на этом устройстве'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textFaint),
            ),
          ),
        ),
      ],
    );
  }

  /// Поле даты рождения: открывает календарь, показывает выбранное и
  /// сразу подписывает получившийся возраст — чтобы промах в году был виден
  /// на месте, а не всплыл в дипломе через полгода.
  Widget _birthField() {
    final b = _birth;
    return PressableScale(
      onTap: _pickBirth,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cake_outlined,
                size: 20, color: AppColors.goldLight),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                b == null
                    ? t('Дата рождения')
                    : '${fmtDateShort(b)} · ${_years(ageFromBirth(b))}',
                style: TextStyle(
                    fontSize: 15,
                    color: b == null
                        ? Colors.white.withValues(alpha: 0.5)
                        : Colors.white),
              ),
            ),
            Icon(Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // Открываем не на сегодняшнем дне, а на разумном году: иначе человеку
      // пришлось бы отлистать три десятка лет назад.
      initialDate: _birth ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: DateTime(now.year - 5, now.month, now.day),
      helpText: t('Дата рождения'),
    );
    if (picked != null) setState(() => _birth = picked);
  }

  /// Кнопка выбора языка на экране регистрации. Устроена как выбор пола
  /// ниже — одинаковые на вид кнопки в одной форме не должны отличаться
  /// поведением.
  Widget _langTab(Lang l, bool active, VoidCallback onTap) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: active ? 0.4 : 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active
                  ? AppColors.gold
                  : Colors.white.withValues(alpha: 0.15),
              width: active ? 1.4 : 1),
        ),
        child: Text(l.label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: active
                    ? AppColors.cream
                    : Colors.white.withValues(alpha: 0.7))),
      ),
    );
  }

  Widget _genderTab(Gender g) {
    final active = _gender == g;
    return PressableScale(
      // Повторное нажатие снимает выбор: раз поле необязательное, человек
      // должен уметь передумать, а не только выбрать.
      onTap: () => setState(() => _gender = _gender == g ? null : g),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: active ? 0.4 : 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active
                  ? AppColors.gold
                  : Colors.white.withValues(alpha: 0.15),
              width: active ? 1.4 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(g == Gender.male ? Icons.male : Icons.female,
                size: 18,
                color: active
                    ? AppColors.cream
                    : Colors.white.withValues(alpha: 0.6)),
            const SizedBox(width: 6),
            Text(t(g.titleRu),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? AppColors.cream
                        : Colors.white.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }

  Widget _tab(String text, bool active, VoidCallback onTap) {
    return Expanded(
      child: PressableScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: active ? 0.4 : 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: active
                    ? AppColors.gold
                    : Colors.white.withValues(alpha: 0.15),
                width: active ? 1.4 : 1),
          ),
          child: Text(t(text),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? AppColors.cream
                      : Colors.white.withValues(alpha: 0.7))),
        ),
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: t(label),
        prefixIcon:
            Icon(icon, color: Colors.white.withValues(alpha: 0.6)),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.3),
        labelStyle:
            TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      );
}

// ------------------------------------------------------------- Профиль

class _Profile extends StatelessWidget {
  final dynamic user;
  const _Profile({required this.user});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tracker = state.tracker!;
    final zikrs = state.zikrs!;
    final now = state.now;

    // --- Статистика намазов за 30 дней ---
    int read = 0, missed = 0, fullDays = 0;
    for (var i = 0; i < 30; i++) {
      final d = DateTime(now.year, now.month, now.day - i);
      read += tracker.readCount(d);
      missed += tracker.missedCount(d);
      if (tracker.readCount(d) == 5) fullDays++;
    }
    var streakStart = DateTime(now.year, now.month, now.day);
    if (tracker.readCount(streakStart) < 5) {
      streakStart = streakStart.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (tracker.readCount(streakStart) == 5) {
      streak++;
      streakStart = streakStart.subtract(const Duration(days: 1));
    }
    final marked = read + missed;
    final pct = marked == 0 ? null : (read / marked * 100).round();

    // --- Статистика зикров ---
    double weekSum = 0;
    for (var i = 0; i < 7; i++) {
      weekSum += zikrs
          .dayCompletion(DateTime(now.year, now.month, now.day - i));
    }
    final zikrAvg = (weekSum / 7 * 100).round();
    final zikrStreak = zikrs.streak(now);
    final goals = zikrs.goals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeSlideIn(
          child: Row(
            children: [
              GlassCard(
                radius: 32,
                darkness: 0.2,
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Center(
                    child: Text(
                      (user.name as String).isEmpty
                          ? '?'
                          : (user.name as String)
                              .characters
                              .first
                              .toUpperCase(),
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.goldLight),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name as String,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    Text(user.phone as String,
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.white
                                .withValues(alpha: 0.7))),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Пол может быть не указан — тогда строку про него
                        // просто не показываем, остаётся возраст.
                        if (user.gender != null) ...[
                          Icon(
                              (user.gender as Gender) == Gender.male
                                  ? Icons.male
                                  : Icons.female,
                              size: 15,
                              color: AppColors.goldLight),
                          const SizedBox(width: 4),
                        ],
                        Text(
                            user.gender == null
                                ? _years(user.age as int)
                                : '${t((user.gender as Gender).titleRu)} · ${_years(user.age as int)}',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.white
                                    .withValues(alpha: 0.75))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FadeSlideIn(
          delay: const Duration(milliseconds: 60),
          child: GlassCard(
            radius: 20,
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.monetization_on,
                        color: AppColors.goldLight, size: 34),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('Мои коины'),
                              style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.white
                                      .withValues(alpha: 0.75))),
                          Text('${state.coins}',
                              style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.goldLight)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _coinBreak(Icons.mosque_outlined, 'Намазы',
                          '${state.prayerCoins}', '5 за намаз'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _coinBreak(Icons.repeat, 'Зикры',
                          '${state.zikrCoins}', '1 за 33 повтора'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: state.earnedCoins / AppState.maxCoins,
                    minHeight: 7,
                    backgroundColor: Colors.black.withValues(alpha: 0.3),
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.gold),
                  ),
                ),
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                      appLang == Lang.ky
                    ? 'Топтолду: ${state.earnedCoins} / ${AppState.maxCoins}'
                    : 'Заработано ${state.earnedCoins} / ${AppState.maxCoins}'
                      '${state.spentCoins > 0 ? ' · потрачено ${state.spentCoins}' : ''}',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6))),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentGreen,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ShopScreen())),
                    icon: const Icon(Icons.storefront_outlined, size: 20),
                    label: Text(t('Магазин наград'),
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 10),
                // Соревнование — рядом с коинами намеренно: очки берутся из
                // тех же намазов и зикров, и человек должен видеть это
                // в одном месте, а не искать таблицу в настройках.
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(
                          color: AppColors.gold.withValues(alpha: 0.55)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RatingScreen())),
                    icon: const Icon(Icons.emoji_events_outlined,
                        size: 20, color: AppColors.goldLight),
                    label: Text(t('Соревнование и друзья'),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.goldLight)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const FadeSlideIn(
          delay: Duration(milliseconds: 90),
          child: _CertificatesEntry(),
        ),
        const SizedBox(height: 14),
        _section('Намазы · 30 дней', 100, [
          _statRow(Icons.check_circle_outline, 'Прочитано', '$read',
              AppColors.accentGreen),
          _statRow(Icons.cancel_outlined, 'Пропущено', '$missed',
              Colors.redAccent),
          _statRow(Icons.percent, 'Выполнение',
              pct == null ? '—' : '$pct%', AppColors.goldLight),
          _statRow(Icons.local_fire_department_outlined,
              'Серия полных дней (5/5)', '$streak', AppColors.gold),
          _statRow(Icons.calendar_month_outlined,
              'Полных дней из 30', '$fullDays', Colors.white70),
        ]),
        const SizedBox(height: 14),
        _section('Зикры', 220, [
          for (final g in goals)
            _zikrProgressRow(
                t(g.title),
                zikrs.countOf(state.todayDate, g.id),
                g.target),
          const SizedBox(height: 6),
          _statRow(Icons.percent, 'Среднее за 7 дней', '$zikrAvg%',
              AppColors.goldLight),
          _statRow(Icons.local_fire_department_outlined,
              'Серия дней (все цели)', '$zikrStreak',
              AppColors.gold),
        ]),
        const SizedBox(height: 14),
        FadeSlideIn(
          delay: const Duration(milliseconds: 320),
          child: GlassCard(
            radius: 20,
            child: Column(
              children: [
                _actionTile(
                    context,
                    Icons.badge_outlined,
                    'Возраст и пол',
                    'Изменить данные профиля',
                    () => _editProfile(context, state, user)),
                Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.1)),
                _actionTile(
                    context,
                    Icons.tune,
                    'Настройки зикров',
                    'Цели: какие зикры и сколько раз в день',
                    () => showZikrSettings(context)),
                Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.1)),
                _actionTile(
                    context,
                    Icons.settings_outlined,
                    'Настройки',
                    'Локация, мазхаб, зикры',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()))),
                Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.1)),
                _actionTile(context, Icons.logout, 'Выйти', null,
                    () => _confirmLogout(context, state),
                    color: Colors.redAccent),
                Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.1)),
                // Требование App Store: аккаунт должен удаляться из самого
                // приложения, а не через обращение в поддержку.
                _actionTile(
                    context,
                    Icons.delete_forever_outlined,
                    'Удалить аккаунт',
                    'Вместе со статистикой и коинами',
                    () => _confirmDelete(context, state),
                    color: Colors.redAccent),
              ],
            ),
          ),
        ),
      ],
    );
  }


  Future<void> _editProfile(
      BuildContext context, AppState state, dynamic user) async {
    DateTime? birth = user.birthDate as DateTime?;
    Gender? gender = user.gender as Gender?;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.skyBottom,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 18,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('Возраст и пол'),
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              PressableScale(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: birth ??
                        DateTime(now.year - 20, now.month, now.day),
                    firstDate: DateTime(now.year - 120),
                    lastDate: DateTime(now.year - 5, now.month, now.day),
                    helpText: t('Дата рождения'),
                  );
                  if (picked != null) setSheet(() => birth = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cake_outlined,
                          size: 20, color: AppColors.goldLight),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          birth == null
                              ? t('Дата рождения')
                              : '${fmtDateShort(birth!)} · '
                                  '${_years(ageFromBirth(birth!))}',
                          style: TextStyle(
                              fontSize: 15,
                              color: birth == null
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : Colors.white),
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: Colors.white.withValues(alpha: 0.4)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final g in Gender.values) ...[
                    Expanded(
                      child: PressableScale(
                        onTap: () => setSheet(() => gender = g),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(
                                alpha: gender == g ? 0.4 : 0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: gender == g
                                    ? AppColors.gold
                                    : Colors.white.withValues(alpha: 0.15),
                                width: gender == g ? 1.4 : 1),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                  g == Gender.male
                                      ? Icons.male
                                      : Icons.female,
                                  size: 18,
                                  color: gender == g
                                      ? AppColors.cream
                                      : Colors.white
                                          .withValues(alpha: 0.6)),
                              const SizedBox(width: 6),
                              Text(t(g.titleRu),
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: gender == g
                                          ? AppColors.cream
                                          : Colors.white
                                              .withValues(alpha: 0.7))),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (g != Gender.values.last) const SizedBox(width: 10),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(t('Сохранить')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) {
      await state.updateProfile(birthDate: birth, gender: gender);
    }
  }

  Future<void> _confirmLogout(
      BuildContext context, AppState state) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.skyBottom,
        title: Text(t('Выйти из аккаунта?')),
        content:
            Text(t('Данные трекера и зикров останутся на устройстве.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Отмена'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Выйти'))),
        ],
      ),
    );
    if (yes == true) await state.logoutAccount();
  }

  /// Удаление аккаунта: два подтверждения — действие необратимое, а рядом
  /// стоит обычный «Выйти», и промахнуться легко.
  Future<void> _confirmDelete(BuildContext context, AppState state) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.skyBottom,
        title: Text(t('Удалить аккаунт?')),
        content: Text(t('Будут стёрты: анкета, история намазов, счётчики '
            'зикров, коины, закладки и заметки в Коране, доступы к курсам. '
            'Восстановить их будет нельзя.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Отмена'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Удалить'),
                  style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final err = await state.deleteAccount();
    messenger.showSnackBar(SnackBar(
      content: Text(err ?? t('Аккаунт удалён')),
      duration: Duration(seconds: err == null ? 3 : 6),
    ));
  }

  Widget _section(String title, int delayMs, List<Widget> children) {
    return FadeSlideIn(
      delay: Duration(milliseconds: delayMs),
      child: GlassCard(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t(title),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _coinBreak(
      IconData icon, String label, String value, String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.goldLight),
              const SizedBox(width: 6),
              Text(t(label),
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.8))),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800)),
          Text(t(hint),
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.55))),
        ],
      ),
    );
  }

  Widget _statRow(
      IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(t(label),
                style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.85))),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }

  Widget _zikrProgressRow(String title, int count, int target) {
    final p = target == 0 ? 0.0 : (count / target).clamp(0.0, 1.0);
    final done = count >= target;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(t(title),
                      style: const TextStyle(fontSize: 14))),
              Text('$count/$target',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: done
                          ? AppColors.accentGreen
                          : Colors.white.withValues(alpha: 0.8))),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              tween: Tween(end: p),
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(
                    done ? AppColors.accentGreen : AppColors.gold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile(BuildContext context, IconData icon, String title,
      String? subtitle, VoidCallback? onTap,
      {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.gold),
      title: Text(t(title),
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(t(subtitle),
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.6))),
      trailing: onTap == null
          ? null
          : Icon(Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.4)),
      onTap: onTap,
    );
  }
}

/// Вход в раздел документов из личного кабинета.
///
/// Скрыт, пока ничего не выдано: пустая карточка «сертификатов нет» на
/// главном экране аккаунта выглядела бы упрёком, а не разделом.
class _CertificatesEntry extends StatelessWidget {
  const _CertificatesEntry();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CertificateService.instance,
      builder: (context, _) {
        final items = CertificateService.instance.items;
        if (items.isEmpty) return const SizedBox.shrink();
        final unseen = CertificateService.instance.unseen;
        return PressableScale(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const CertificatesScreen())),
          child: GlassCard(
            radius: 20,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_outlined,
                    color: AppColors.goldLight, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('Мои сертификаты'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(
                        unseen > 0
                            ? '${items.length} · ${t('новых')}: $unseen'
                            : '${items.length}',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: Colors.white.withValues(alpha: 0.6)),
              ],
            ),
          ),
        );
      },
    );
  }
}
