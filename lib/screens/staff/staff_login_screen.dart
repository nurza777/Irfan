import 'package:flutter/material.dart';

import '../../services/staff_auth.dart';
import '../../theme.dart';
import '../../widgets/dome_background.dart';
import '../../widgets/glass.dart';
import 'staff_home.dart';

/// Вход устаза в кабинет по логину и паролю, которые выдал администратор.
///
/// Своей регистрации здесь нет намеренно: право публиковать уроки ученикам
/// не должно выдаваться самим по себе — учётку заводит админ в веб-панели.
class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final _login = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await StaffAuth.instance.login(_login.text, _pass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err != null) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const StaffHome()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DomeBackground(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, color: AppColors.cream),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.school_outlined,
                            color: AppColors.gold, size: 40),
                        const SizedBox(height: 12),
                        const Text('Кабинет устаза',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.cream,
                                fontSize: 20,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        const Text(
                          'Раздел для преподавателей: эфир, курсы, новости '
                          'и азкары. Логин и пароль выдаёт администратор.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textFaint, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _login,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(color: AppColors.cream),
                          decoration: const InputDecoration(
                            labelText: 'Логин',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pass,
                          obscureText: _hide,
                          autocorrect: false,
                          enableSuggestions: false,
                          onSubmitted: (_) => _submit(),
                          style: const TextStyle(color: AppColors.cream),
                          decoration: InputDecoration(
                            labelText: 'Пароль',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_hide
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _hide = !_hide),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.redAccent, fontSize: 13)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.domeDark))
                              : const Text('Войти'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
