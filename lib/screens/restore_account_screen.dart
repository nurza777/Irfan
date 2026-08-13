import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../services/account_backup.dart';
import '../services/auth_service.dart' show normalizePhone;
import '../services/date_fmt.dart';
import '../services/lang.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import '../widgets/support_card.dart';
import 'verify_phone_screen.dart';

/// Перенос аккаунта на этот телефон.
///
/// Аккаунт живёт на устройстве, и до этого экрана смена телефона означала
/// потерю серии, коинов и всей истории намазов — вернуть их было нечем.
///
/// Два пути внутрь, и первый пробуется молча:
///   * телефон уже закреплён за записью (приложение переустановили: Keychain
///     переустановку переживает, а хранилище нет) — код не нужен;
///   * иначе номер подтверждается кодом, и запись переезжает сюда.
class RestoreAccountScreen extends StatefulWidget {
  /// Подставленный номер. Нужен только отладочному хуку: в симуляторе печатать
  /// нечем, а проверять экран надо (см. root_screen, значение `restore`).
  final String phone;
  const RestoreAccountScreen({super.key, this.phone = ''});

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
    // Номер подставлен — значит, экран открыт отладочным хуком, и нажимать
    // «Продолжить» в симуляторе некому.
    if (widget.phone.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  // ── Шаг 1: номер ───────────────────────────────────────────────────────

  Future<void> _lookup() async {
    final phone = normalizePhone(_phone.text);
    if (phone.isEmpty) {
      setState(() => _error = t('Некорректный номер телефона'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    var r = await AccountRestore.fetch(phone);
    // Кода просит только сервер и только когда этот телефон записи не
    // принадлежит. Экран подтверждения открываем сами и берём у него
    // одноразовое разрешение.
    if (r.status == RestoreStatus.needsCode && mounted) {
      final ticket = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => VerifyPhoneScreen(phone: phone)),
      );
      if (!mounted) return;
      if (ticket == null || ticket.isEmpty) {
        setState(() => _busy = false);
        return;
      }
      r = await AccountRestore.fetch(phone, ticket: ticket);
    }
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
          RestoreStatus.needsCode => t('Номер не подтверждён'),
          RestoreStatus.offline => t('Нет связи с сервером — попробуйте позже'),
          _ => t('Не удалось восстановить аккаунт'),
        };
      }
    });
  }

  // ── Шаг 2: новый пароль и перенос ──────────────────────────────────────

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
              if (_found == null) ..._askPhone() else ..._askPassword(_found!),
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
          t('Введите номер, на который был заведён аккаунт. Серия, коины и '
              'история намазов вернутся на этот телефон.'),
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
          text: t('Если это новый телефон, понадобится код подтверждения — '
              'его называет устаз.'),
        ),
      ];

  List<Widget> _askPassword(RestoreResult r) => [
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
                t('Придумайте пароль для входа на этом телефоне. Прежний не '
                    'подойдёт: пароль хранится только на устройстве и на '
                    'сервер не уходит.'),
                style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.7)),
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
                onSubmitted: (_) => _busy ? null : _restore(),
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
