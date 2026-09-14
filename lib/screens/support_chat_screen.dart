import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/date_fmt.dart';
import '../services/lang.dart';
import '../services/support_chat_service.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';

/// Переписка с поддержкой.
///
/// Раньше связаться можно было только через мессенджеры или звонок — то есть
/// выйдя из приложения. Часть людей на этом и останавливалась: чужой мессенджер
/// не у всех, а звонить незнакомому человеку решается не каждый.
///
/// Ответ приходит не мгновенно: с той стороны живой человек, а не робот.
/// Поэтому переписка сохраняется на сервере и ждёт — вернуться за ответом
/// можно когда угодно, хоть на другой день.
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<SupportMessage>? _messages;
  bool _sending = false;
  SupportChatStatus _status = SupportChatStatus.ok;
  Timer? _poll;
  String _phone = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _phone = AppScope.of(context).auth?.current?.phone ?? '';
      // Без аккаунта переписки нет и быть не может: ветка заводится на
      // номер. Раньше здесь просто выходили из _load, и человек оставался
      // перед вечным кружком загрузки.
      if (_phone.isEmpty) {
        setState(() {});   // покажем объяснение вместо переписки
        return;
      }
      _load();
      // Пока экран открыт — спрашиваем сервер о новых сообщениях. Пушей
      // об ответе поддержки пока нет (нужен ключ APNs), и без опроса ответ
      // появлялся бы только при следующем заходе.
      //
      // Раз в 15 секунд, а не чаще: с той стороны живой человек, ответ идёт
      // минутами, и учащать значит впустую жечь связь и батарею.
      _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_phone.isEmpty) return;
    // Держались ли мы конца списка ДО обновления — от этого зависит,
    // прокручивать ли вниз (см. _toBottom).
    final wasAtBottom = _atBottom;
    final res = await SupportChatService.history(_phone);
    if (!mounted) return;
    final grew = res.status == SupportChatStatus.ok &&
        res.messages.length != (_messages?.length ?? 0);
    setState(() {
      _status = res.status;
      if (res.status == SupportChatStatus.ok) _messages = res.messages;
    });
    if (grew && wasAtBottom) _toBottom();
  }

  /// Человек смотрит на конец переписки (с запасом в экранную сотню точек).
  bool get _atBottom {
    if (!_scroll.hasClients) return true;   // ещё не построен — считаем, что да
    final p = _scroll.position;
    return p.maxScrollExtent - p.pixels < 100;
  }

  /// Прокрутка вниз — ТОЛЬКО когда человек и так внизу.
  ///
  /// Раньше звалась после каждого опроса. Стоило отлистать переписку вверх,
  /// чтобы перечитать прошлый ответ, — и через несколько секунд экран сам
  /// уезжал в конец. Читать старое было невозможно.
  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final name = AppScope.of(context).auth?.current?.name ?? '';
    final msg = await SupportChatService.send(_phone, text, name: name);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (msg != null) {
        _input.clear();
        _messages = [...?_messages, msg];
      }
    });
    if (msg == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('Не удалось отправить — проверьте связь'))));
    }
    _toBottom();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = _messages;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Text(t('Поддержка')),
      ),
      body: DomeBackground(
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + 8),
              if (_phone.isEmpty)
                Expanded(child: Center(child: _needAccount()))
              else
              Expanded(
                child: msgs == null
                    ? Center(child: _placeholder())
                    : msgs.isEmpty
                        ? _empty()
                        : ListView.builder(
                            controller: _scroll,
                            padding:
                                const EdgeInsets.fromLTRB(14, 8, 14, 12),
                            itemCount: msgs.length,
                            itemBuilder: (_, i) => _Bubble(m: msgs[i]),
                          ),
              ),
              // Без аккаунта поле ввода не показываем вовсе: ветка переписки
              // заводится на номер, и отправлять было бы некуда. Пустое поле
              // с кнопкой, которая всегда отвечает ошибкой, — обман.
              if (_phone.isNotEmpty) _composer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _needAccount() => Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline,
                size: 52, color: AppColors.textFaint),
            const SizedBox(height: 14),
            Text(
              t('Переписка привязана к вашему номеру — войдите в аккаунт '
                  'или зарегистрируйтесь, и сможете написать нам отсюда.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14.5,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 6),
            Text(t('Телефон и мессенджеры поддержки — в настройках.'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textFaint)),
          ],
        ),
      );

  /// Что показать, пока сообщений нет вовсе.
  Widget _placeholder() {
    if (_status == SupportChatStatus.offline) {
      return Text(t('Нет связи с сервером'),
          style: const TextStyle(color: AppColors.textFaint));
    }
    if (_status == SupportChatStatus.denied) {
      // Сервер не признал устройство. Совет проверить интернет тут был бы
      // вредным: связь есть, дело в другом.
      return Padding(
        padding: const EdgeInsets.all(30),
        child: Text(
          t('Переписка недоступна на этом устройстве. '
              'Если вы переносили аккаунт, войдите заново.'),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 14.5,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.7)),
        ),
      );
    }
    return const CircularProgressIndicator(color: AppColors.gold);
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum_outlined,
                  size: 52, color: AppColors.textFaint),
              const SizedBox(height: 14),
              Text(
                t('Напишите нам — ответим, как только увидим сообщение.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      );

  Widget _composer() => Padding(
        padding: EdgeInsets.fromLTRB(
            12, 6, 12, MediaQuery.of(context).viewInsets.bottom + 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: t('Сообщение…'),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PressableScale(
              onTap: _sending ? null : _send,
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                    color: AppColors.accentGreen, shape: BoxShape.circle),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      );
}

class _Bubble extends StatelessWidget {
  final SupportMessage m;
  const _Bubble({required this.m});

  /// Время сообщения: сегодняшние — часами, прежние — ещё и датой.
  /// Дата у сообщения, отправленного пять минут назад, только мешает.
  String _stamp(DateTime at) {
    final now = DateTime.now();
    final today = at.year == now.year && at.month == now.month &&
        at.day == now.day;
    final hhmm = '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    return today ? hhmm : '${fmtDateShort(at)}, $hhmm';
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: m.mine
              ? AppColors.accentGreen.withValues(alpha: 0.85)
              : Colors.black.withValues(alpha: 0.38),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(m.mine ? 16 : 4),
            bottomRight: Radius.circular(m.mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!m.mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(t('Поддержка'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.goldLight)),
              ),
            Text(m.text,
                style: const TextStyle(fontSize: 15, height: 1.35)),
            const SizedBox(height: 3),
            Text(_stamp(m.at),
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }
}
