import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/auth_service.dart';
import '../services/lang.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';
import 'verify_phone_screen.dart';
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
  final _age = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _phone.dispose();
    _city.dispose();
    _email.dispose();
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
            email: _email.text, password: _password.text)
        : await state.registerAccount(
            name: _name.text,
            email: _email.text,
            password: _password.text,
            age: int.tryParse(_age.text.trim()) ?? 0,
            gender: _gender,
            phone: _phone.text,
            city: _city.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    // Успешная регистрация — сразу просим подтвердить телефон.
    if (err == null && !_isLogin) {
      final u = state.auth?.current;
      if (u != null && u.phone.isNotEmpty) {
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                VerifyPhoneScreen(email: u.email, phone: u.phone),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                              child: TextField(
                                controller: _age,
                                keyboardType: TextInputType.number,
                                decoration:
                                    _dec('Возраст', Icons.cake_outlined),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                decoration: _dec('Телефон', Icons.phone_outlined)
                                    .copyWith(hintText: '0555 12 34 56'),
                              ),
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
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: _dec('Email', Icons.mail_outline),
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
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 14)),
                        ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentGreen,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : Text(
                            _isLogin ? t('Войти') : t('Создать аккаунт'),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        FadeSlideIn(
          delay: const Duration(milliseconds: 200),
          child: Text(
            t('Аккаунт хранится локально на этом устройстве'),
            style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.55)),
          ),
        ),
      ],
    );
  }

  Widget _genderTab(Gender g) {
    final active = _gender == g;
    return PressableScale(
      onTap: () => setState(() => _gender = g),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: active ? 0.4 : 0.15),
          borderRadius: BorderRadius.circular(14),
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: active ? 0.4 : 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: active
                    ? AppColors.gold
                    : Colors.white.withValues(alpha: 0.15),
                width: active ? 1.4 : 1),
          ),
          child: Text(t(text),
              style: TextStyle(
                  fontSize: 15,
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
                    Text(user.email as String,
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.white
                                .withValues(alpha: 0.7))),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                            (user.gender as Gender) == Gender.male
                                ? Icons.male
                                : Icons.female,
                            size: 15,
                            color: AppColors.goldLight),
                        const SizedBox(width: 4),
                        Text(
                            '${t((user.gender as Gender).titleRu)} · ${_years(user.age as int)}',
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
              ],
            ),
          ),
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
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _years(int n) {
    if (appLang == Lang.ky) return '$n жаш';
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return '$n год';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n года';
    return '$n лет';
  }

  Future<void> _editProfile(
      BuildContext context, AppState state, dynamic user) async {
    final ageCtrl = TextEditingController(
        text: (user.age as int) > 0 ? '${user.age}' : '');
    var gender = user.gender as Gender;
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
              TextField(
                controller: ageCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t('Возраст'),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
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
      final age = int.tryParse(ageCtrl.text.trim());
      await state.updateProfile(
          age: (age != null && age >= 5 && age <= 120) ? age : null,
          gender: gender);
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
