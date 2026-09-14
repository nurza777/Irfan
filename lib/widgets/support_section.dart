import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../services/lang.dart';
import '../screens/support_chat_screen.dart';
import '../services/support_chat_service.dart';
import '../services/support_service.dart';
import '../theme.dart';
import 'glass.dart';

/// Раздел «Поддержка» в настройках: позвонить живому человеку.
///
/// Прежде связаться с организацией можно было только с двух экранов —
/// подтверждения номера и переноса аккаунта, — и только через мессенджеры.
/// Человек, у которого вопрос не про код, кнопок не находил вовсе.
///
/// Контакты приходят с сервера и меняются в админ-панели без пересборки
/// приложения: номера у организаций меняются чаще, чем выходят обновления
/// в App Store. Пока админ ничего не заполнил, раздела просто нет — пустая
/// карточка «свяжитесь с нами» без единого способа связаться хуже, чем
/// её отсутствие.
class SupportSection extends StatefulWidget {
  const SupportSection({super.key});

  @override
  State<SupportSection> createState() => _SupportSectionState();
}

class _SupportSectionState extends State<SupportSection> {
  SupportContact? _contact;

  @override
  void initState() {
    super.initState();
    SupportService.get().then((c) {
      if (mounted) setState(() => _contact = c);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SupportChatService.refreshUnread(
          AppScope.of(context).auth?.current?.phone);
    });
  }

  Future<void> _open(String url) async {
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('Не удалось открыть'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _contact;
    // Ждём ответа сервера — места не занимаем. А вот пустой набор контактов
    // раздел больше не прячет: переписка доступна всегда, даже когда админ
    // не завёл ни номера, ни мессенджера.
    if (c == null) return const SizedBox.shrink();
    final muted = Colors.white.withValues(alpha: 0.6);
    final rows = <Widget>[];

    void divider() => rows.add(Divider(
        height: 1, color: Colors.white.withValues(alpha: 0.1)));

    // Переписка — первой: она не зависит ни от часа, ни от того, возьмут ли
    // трубку, и остаётся единственным способом связи для тех, кому неудобно
    // звонить. Ответ придёт не сразу, и об этом сказано прямо в подписи.
    rows.add(ListTile(
      leading: const Icon(Icons.forum_outlined, color: AppColors.gold),
      title: Text(t('Написать в поддержку'),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(t('Ответим в приложении, как увидим сообщение'),
          style: TextStyle(fontSize: 13, color: muted)),
      trailing: ValueListenableBuilder<int>(
        valueListenable: SupportChatService.unreadCount,
        builder: (context, n, _) => n > 0
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$n',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black)),
              )
            : const Icon(Icons.chevron_right, color: Colors.white54),
      ),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const SupportChatScreen())),
    ));

    for (final p in c.phones) {
      if (rows.isNotEmpty) divider();
      rows.add(ListTile(
        leading: const Icon(Icons.call_outlined, color: AppColors.gold),
        // Первой строкой — номер: звонят по нему, а имя лишь поясняет, кто
        // ответит. Если имени нет, подписи не будет вовсе.
        title: Text(p.phone,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: p.name.isEmpty
            ? null
            : Text(p.name, style: TextStyle(fontSize: 13, color: muted)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        onTap: () => _open(p.telUrl),
      ));
    }

    final wa = c.whatsappUrl;
    if (wa != null) {
      if (rows.isNotEmpty) divider();
      rows.add(ListTile(
        leading: const Icon(Icons.chat_outlined, color: AppColors.gold),
        title: const Text('WhatsApp'),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        onTap: () => _open(wa),
      ));
    }
    final tg = c.telegramUrl;
    if (tg != null) {
      if (rows.isNotEmpty) divider();
      rows.add(ListTile(
        leading: const Icon(Icons.send_outlined, color: AppColors.gold),
        title: const Text('Telegram'),
        subtitle: Text('@${c.telegram}',
            style: TextStyle(fontSize: 13, color: muted)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        onTap: () => _open(tg),
      ));
    }

    return GlassCard(
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Row(
              children: [
                const Icon(Icons.support_agent, color: AppColors.gold),
                const SizedBox(width: 10),
                Text(t('Поддержка'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (c.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(c.note,
                  style: TextStyle(fontSize: 13, height: 1.35, color: muted)),
            ),
          ...rows,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
