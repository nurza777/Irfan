import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../services/lang.dart';
import '../services/private_zikr_service.dart';
import '../theme.dart';
import '../widgets/glass.dart';

/// Закрытые зикры — личные обеты с планом на день и напоминаниями.
/// Живут в настройках зикров: на самом экране счётчика они оттягивали
/// внимание от того, ради чего экран открывают, — от круга.
class PrivateZikrSection extends StatelessWidget {
  const PrivateZikrSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final svc = state.privateZikrs;
    if (svc == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final list = svc.all;
        final day = state.todayDate;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: AppColors.goldLight,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t('Закрытые зикры'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                PressableScale(
                  onTap: () => _edit(context, svc),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.add_circle_outline,
                      color: AppColors.gold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  t(
                    'Свой обет: название, сколько раз в день и когда напомнить.',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              )
            else
              for (final z in list)
                _PrivateZikrTile(
                  zikr: z,
                  done: svc.doneToday(day, z.id),
                  onAdd: () => _addProgress(context, svc, day, z),
                  onEdit: () => _edit(context, svc, existing: z),
                ),
          ],
        );
      },
    );
  }

  Future<void> _addProgress(
    BuildContext context,
    PrivateZikrService svc,
    DateTime day,
    PrivateZikr z,
  ) => showPrivateZikrProgress(context, svc, day, z);
}

/// Диалог «сколько сделал»: вписанное вычитается из остатка.
///
/// Общий и для раздела закрытых зикров, и для ряда названий вверху экрана
/// зикров: способ заполнения у обета один и тот же, где бы его ни открыли.
Future<void> showPrivateZikrProgress(
  BuildContext context,
  PrivateZikrService svc,
  DateTime day,
  PrivateZikr z,
) async {
  // Messenger берём ДО диалога и больше к context не обращаемся.
  //
  // Обращение к нему после await — это подписка на унаследованный виджет из
  // контекста, который к тому моменту может уже разбираться (обет теперь
  // открывают и из прокручиваемого ряда, элементы которого переиспользуются).
  // Ровно на этом падал ассерт _dependents.isEmpty.
  final messenger = ScaffoldMessenger.of(context);
  final left = svc.leftToday(day, z);
  if (left == 0) {
    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.skyBottom,
        title: Text(t('Уже закрыт на сегодня')),
        content: Text(t('Начать счёт заново?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Отмена')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Сбросить')),
          ),
        ],
      ),
    );
    if (again == true) await svc.resetToday(day, z);
    return;
  }

  final ctrl = TextEditingController();
  final n = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.skyBottom,
      title: Text(z.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${t('Осталось')}: $left', style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '$left',
              labelText: t('Сколько сделали'),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim()) ?? 0),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 0),
          child: Text(t('Отмена')),
        ),
        // Частый случай — дочитал остаток целиком.
        TextButton(
          onPressed: () => Navigator.pop(ctx, left),
          child: Text(t('Всё')),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(ctx, int.tryParse(ctrl.text.trim()) ?? 0),
          child: Text(t('Записать')),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (n == null || n <= 0) return;
  final rest = await svc.addProgress(day, z, n);
  HapticFeedback.mediumImpact();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        rest == 0
            ? '${z.title} — ${t('закрыт на сегодня')}'
            : '${t('Осталось')}: $rest',
      ),
    ),
  );
}

/// Создание и правка обета.
Future<void> _edit(
  BuildContext context,
  PrivateZikrService svc, {
  PrivateZikr? existing,
}) async {
  // Так же, как выше: до диалога, а не после.
  final app = AppScope.of(context);
  final title = TextEditingController(text: existing?.title ?? '');
  final target = TextEditingController(text: '${existing?.target ?? 100}');
  var times = [...(existing?.reminders ?? const <ZikrReminder>[])];

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: AppColors.skyBottom,
        title: Text(
          existing == null ? t('Новый закрытый зикр') : t('Закрытый зикр'),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: title,
                decoration: InputDecoration(labelText: t('Название')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: target,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t('Сколько раз в день')),
              ),
              const SizedBox(height: 14),
              Text(
                t('Когда напоминать'),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (i, r) in times.indexed)
                    InputChip(
                      label: Text(r.label),
                      onDeleted: () => setLocal(() => times.removeAt(i)),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text(t('Время')),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: const TimeOfDay(hour: 9, minute: 0),
                      );
                      if (picked != null) {
                        setLocal(
                          () => times.add(
                            ZikrReminder(picked.hour, picked.minute),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              if (times.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    t('Без времени напоминаний не будет — просто счёт.'),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                await svc.remove(existing.id);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: Text(
                t('Удалить'),
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Сохранить')),
          ),
        ],
      ),
    ),
  );

  final name = title.text.trim();
  final n = int.tryParse(target.text.trim()) ?? 0;
  title.dispose();
  target.dispose();

  if (saved != true || name.isEmpty || n <= 0) return;

  if (existing == null) {
    await svc.add(title: name, target: n, reminders: times);
  } else {
    await svc.update(
      existing.copyWith(title: name, target: n, reminders: times),
    );
  }
  // Напоминания меняются вместе с обетом.
  await app.rescheduleNotifications();
}

class _PrivateZikrTile extends StatelessWidget {
  final PrivateZikr zikr;
  final int done;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  const _PrivateZikrTile({
    required this.zikr,
    required this.done,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final left = (zikr.target - done).clamp(0, zikr.target);
    final closed = left == 0;
    final p = zikr.target == 0 ? 0.0 : done / zikr.target;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableScale(
        onTap: onAdd,
        child: GlassCard(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Icon(
                closed ? Icons.check_circle : Icons.radio_button_unchecked,
                color: closed
                    ? AppColors.accentGreen
                    : Colors.white.withValues(alpha: 0.5),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zikr.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: p.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation(
                          closed ? AppColors.accentGreen : AppColors.goldLight,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      closed
                          ? t('закрыт на сегодня')
                          : '$done / ${zikr.target} · ${t('осталось')} $left',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                    if (zikr.reminders.isNotEmpty)
                      Text(
                        zikr.reminders.map((r) => r.label).join(' · '),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.goldLight.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: Icon(
                  Icons.more_horiz,
                  color: Colors.white.withValues(alpha: 0.6),
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
