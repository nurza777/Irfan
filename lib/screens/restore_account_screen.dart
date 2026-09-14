import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../services/account_backup.dart';
import '../services/auth_service.dart'
    show AuthService, normalizePhone;
import '../services/date_fmt.dart';
import '../services/lang.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import '../widgets/support_card.dart';

/// Перенос аккаунта на этот телефон.
///
/// Аккаунт живёт на устройстве, и до этого экрана смена телефона означала
/// потерю серии, коинов и всей истории намазов — вернуть их было нечем.
///
/// Внутрь пускает номер и пароль — те же, с которыми человек заходил на
/// прежнем телефоне. Сервер сверяет пароль с записанным и отдаёт аккаунт.
///
/// Кода подтверждения здесь БОЛЬШЕ НЕТ. Автоотправка не подключена, код
/// диктовал устаз вручную, и человек упирался в ожидание на ровном месте.
/// По решению владельца вход идёт сразу.
class RestoreAccountScreen extends StatefulWidget {
  /// Подставленный номер. Нужен только отладочному хуку: в симуляторе печатать
  /// нечем, а проверять экран надо (см. root_screen, значение `restore`).
  final String phone;

  /// Подставленный пароль — тем же хуком и по той же причине.
  final String password;
  const RestoreAccountScreen(
      {super.key, this.phone = '', this.password = ''});

  @override
  State<RestoreAccountScreen> createState() => _RestoreAccountScreenState();
}

class _RestoreAccountScreenState extends State<RestoreAccountScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  /// Что вернул сервер. Пока null — показываем ввод номера.
  RestoreResult? _found;
  String _foundPhone = '';

  @override
  void initState() {
    super.initState();
    _phone.text = widget.phone;
    _password.text = widget.password;
    // Поля подставлены — значит, экран открыт отладочным хуком, и нажимать
    // «Продолжить» в симуляторе некому.
    if (widget.phone.isNotEmpty && widget.password.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  // ── Шаг 1: номер и пароль ──────────────────────────────────────────────

  Future<void> _lookup() async {
    final phone = normalizePhone(_phone.text);
    if (phone.isEmpty) {
      setState(() => _error = t('Некорректный номер телефона'));
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = t('Пароль — минимум 6 символов'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Серверу уходит не пароль, а доказательство: PBKDF2 от пароля с солью
    // из номера. На любом телефоне значение одно и то же — потому вход и
    // работает с нового устройства.
    final proof = await AuthService.makeProof(phone, _password.text);
    final r = await AccountRestore.fetch(phone, pass: proof);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.isOk) {
        _found = r;
        _foundPhone = phone;
        _error = null;
      } else {
        _error = switch (r.status) {
          RestoreStatus.notFound => t('На этом номере аккаунта нет'),
          RestoreStatus.blocked =>
            t('Аккаунт заблокирован администратором'),
          RestoreStatus.badPassword => t('Неверный пароль'),
          RestoreStatus.needsCode =>
            t('Не удалось войти — обратитесь в поддержку'),
          RestoreStatus.offline => t('Нет связи с сервером — попробуйте позже'),
          _ => t('Не удалось восстановить аккаунт'),
        };
      }
    });
  }

  // ── Шаг 2: подтверждение переноса ──────────────────────────────────────

  Future<void> _restore() async {
    final r = _found;
    if (r == null) return;
    // AppScope берём ДО await: после него контекст может уже разбираться.
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await state.restoreAccount(r,
        phone: _foundPhone, password: _password.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    HapticFeedback.mediumImpact();
    navigator.pop(true);
  }

  // ── Вид ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(t('Восстановить аккаунт')),
        centerTitle: true,
      ),
      body: DomeBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              const SizedBox(height: 14),
              const Icon(Icons.restore, size: 52, color: AppColors.goldLight),
              const SizedBox(height: 16),
              if (_found == null) ..._askPhone() else ..._confirm(_found!),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _askPhone() => [
        Text(
          t('Введите номер и пароль, с которыми вы заходили на прежнем '
              'телефоне. Серия, коины и история намазов вернутся сюда.'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, height: 1.45),
        ),
        const SizedBox(height: 18),
        GlassCard(
          radius: 20,
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: t('Телефон'),
                  hintText: '+996 555 12 34 56',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onSubmitted: (_) => _busy ? null : _lookup(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: t('Пароль'),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onSubmitted: (_) => _busy ? null : _lookup(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: const Color(0xFF20180A),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _busy ? null : _lookup,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF20180A)))
                      : Text(t('Продолжить'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SupportCard(
          text: t('Забыли пароль? Позвоните нам — восстановим доступ.'),
        ),
      ];

  List<Widget> _confirm(RestoreResult r) => [
        Text(
          r.name.isEmpty ? _foundPhone : r.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _summary(r),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 18),
        GlassCard(
          radius: 20,
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Text(
                t('Аккаунт переедет на этот телефон вместе с историей. '
                    'Пароль останется прежним, а на старом устройстве '
                    'аккаунт больше отмечать намазы не будет — иначе две '
                    'истории разошлись бы.'),
                style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentGreen,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _busy ? null : _restore,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t('Восстановить'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ];

  /// Что именно вернётся — человеку надо видеть, за чем он пришёл.
  String _summary(RestoreResult r) {
    if (!r.hasData) {
      // Аккаунт есть, а слепка нет: он заводился на сборке без переноса и с
      // тех пор не выходил на связь. Обещать историю в этом случае нельзя.
      return t('Анкета найдена, но сохранённой истории нет — она появится '
          'только у аккаунтов, работавших на новой версии приложения.');
    }
    final days = _dayCount(r.data!);
    final when = r.updatedAt;
    final parts = <String>[
      if (days > 0) '${t('дней в трекере')}: $days',
      if (when != null) '${t('слепок от')} ${fmtDateShort(when)}',
    ];
    return parts.isEmpty ? t('История найдена') : parts.join(' · ');
  }

  static int _dayCount(Map<String, dynamic> data) {
    final s = data['s'];
    if (s is! Map) return 0;
    return s.keys.where((k) => '$k'.startsWith('tracker_')).length;
  }
}
