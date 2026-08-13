import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/lang.dart';
import '../services/verify_service.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/support_card.dart';

/// Подтверждение телефона после регистрации.
///
/// Код генерирует сервер; он же следит за сроком и числом попыток. Пока
/// автоотправка не подключена, код выдаёт устаз — об этом прямо написано на
/// экране вместе с кнопками связи, чтобы человек не ждал сообщения впустую.
///
/// Экран возвращает разрешение на перенос аккаунта (см. [VerifyResult.ticket])
/// или null, если человек ушёл, не подтвердив. Разрешением пользуется экран
/// восстановления; при обычной регистрации оно просто не нужно.
class VerifyPhoneScreen extends StatefulWidget {
  final String phone;
  const VerifyPhoneScreen({super.key, required this.phone});

  @override
  State<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends State<VerifyPhoneScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _sending = false;
  String? _error;
  String? _info;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _request() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final r = await VerifyService.requestCode(widget.phone);
    if (!mounted) return;
    setState(() {
      _sending = false;
      switch (r.status) {
        case VerifyStatus.ok:
          _info = r.delivered
              ? t('Код отправлен на ваш номер')
              : t('Код готов — попросите его у устаза');
          _startCooldown(60);
        case VerifyStatus.tooSoon:
          _startCooldown(r.retryAfter ?? 60);
        case VerifyStatus.offline:
          _error = t('Нет связи с сервером — попробуйте позже');
        default:
          _error = t('Не удалось запросить код');
      }
    });
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length < 4) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await VerifyService.confirm(widget.phone, code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.isOk) {
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, r.ticket);
      return;
    }
    setState(() {
      _error = switch (r.status) {
        VerifyStatus.wrongCode => r.attemptsLeft == null
            ? t('Неверный код')
            : '${t('Неверный код')} · ${t('осталось попыток')}: '
                '${r.attemptsLeft}',
        VerifyStatus.expired => t('Код истёк — запросите новый'),
        VerifyStatus.tooManyAttempts =>
          t('Слишком много попыток — запросите новый код'),
        VerifyStatus.offline => t('Нет связи с сервером — попробуйте позже'),
        _ => t('Не удалось подтвердить код'),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(t('Подтверждение номера')),
        centerTitle: true,
      ),
      body: DomeBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            children: [
              const SizedBox(height: 20),
              const Icon(Icons.sms_outlined,
                  size: 56, color: AppColors.goldLight),
              const SizedBox(height: 16),
              // Не пишем «код отправлен»: автоотправка не подключена, и
              // человек (в том числе проверяющий из App Store) ждал бы
              // сообщения, которое не придёт. Что произошло на самом деле,
              // говорит строка ниже — по ответу сервера.
              Text(
                '${t('Подтверждение номера')}\n${widget.phone}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 20),
              SupportCard(text: supportVerifyText()),
              const SizedBox(height: 20),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(
                    fontSize: 30, letterSpacing: 10, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _confirm(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 13)),
              ] else if (_info != null) ...[
                const SizedBox(height: 8),
                Text(_info!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentGreen,
                    padding: const EdgeInsets.symmetric(vertical: 15)),
                onPressed: _busy ? null : _confirm,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(t('Подтвердить')),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: (_cooldown > 0 || _sending) ? null : _request,
                child: Text(_cooldown > 0
                    ? '${t('Запросить снова через')} $_cooldown ${t('с')}'
                    : t('Запросить код снова')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(t('Подтвердить позже'),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
