import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/lang.dart';
import '../services/support_service.dart';
import '../theme.dart';
import 'glass.dart';

/// Карточка «обратитесь к нам» с кнопками связи.
///
/// Показывается там, где человек сам не справится: забыл пароль. Пароль
/// сбрасывает админ в панели, и одной фразы «обратитесь к администратору»
/// мало — ученик оставался бы с ней один на один, не зная, куда звонить.
///
/// Контакт приходит с сервера и может быть не заполнен — тогда показывается
/// одна фраза, без мёртвых кнопок.
class SupportCard extends StatefulWidget {
  /// Пояснение над кнопками.
  final String text;
  const SupportCard({super.key, required this.text});

  @override
  State<SupportCard> createState() => _SupportCardState();
}

class _SupportCardState extends State<SupportCard> {
  SupportContact? _contact;

  @override
  void initState() {
    super.initState();
    SupportService.get().then((c) {
      if (mounted) setState(() => _contact = c);
    });
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = _contact;
    final muted = Colors.white.withValues(alpha: 0.75);
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: AppColors.gold, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.text,
                    style: TextStyle(
                        fontSize: 12, height: 1.35, color: muted)),
              ),
            ],
          ),
          if (c != null && c.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(c.note,
                style: TextStyle(fontSize: 12, height: 1.35, color: muted)),
          ],
          // Звонок — первым и во всю ширину: на этом экране человеку нужен
          // код прямо сейчас, а голосом его называют быстрее, чем пишут.
          if (c != null)
            for (final p in c.phones) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _open(p.telUrl),
                  icon: const Icon(Icons.call, size: 18),
                  label: Text(p.name.isEmpty
                      ? '${t('Позвонить')} ${p.phone}'
                      : '${t('Позвонить')}: ${p.name}'),
                ),
              ),
            ],
          if (c != null && !c.isEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (c.whatsappUrl != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _open(c.whatsappUrl!),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                if (c.whatsappUrl != null && c.telegramUrl != null)
                  const SizedBox(width: 10),
                if (c.telegramUrl != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _open(c.telegramUrl!),
                      icon: const Icon(Icons.send_outlined, size: 18),
                      label: const Text('Telegram'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Текст для экрана подтверждения номера.
String supportVerifyText() => t(
    'Автоматическая отправка не подключена. Позвоните в поддержку: '
    'вам назовут код или подтвердят номер сами — тогда вводить ничего '
    'не нужно, экран закроется сам. Код действует час.');
