import 'package:flutter/material.dart';

import '../app_state.dart';
import '../screens/account_screen.dart';
import '../services/lang.dart';
import '../theme.dart';
import 'glass.dart';

/// Что открывается только после регистрации.
///
/// Без аккаунта приложение показывает время намаза, Коран, киблу и настройки —
/// то, что работает само по себе. Остальное завязано на учётную запись:
/// трекер намазов и серия, счётчик зикров, коины и награды, курсы устаза,
/// прямой эфир, новости.
///
/// Закрытые разделы **не прячутся, а показываются с замком**: иначе человек не
/// узнает, что в приложении вообще есть курсы и эфир, и регистрироваться ему
/// будет незачем.
class AccountGate {
  const AccountGate._();

  /// Есть ли вошедший ученик.
  static bool isOpen(BuildContext context) =>
      AppScope.of(context).auth?.current != null;

  /// Пускает дальше или показывает приглашение. true — можно открывать.
  ///
  /// [feature] — название раздела в винительном падеже, подставляется в
  /// строку «Чтобы открыть …».
  static Future<bool> allow(BuildContext context, String feature) async {
    if (isOpen(context)) return true;
    await invite(context, feature);
    return false;
  }

  /// Показывает, что даёт регистрация, и ведёт на экран аккаунта.
  static Future<void> invite(BuildContext context, String feature) async {
    // Navigator берём ДО await: после закрытия листа контекст может уже
    // разбираться (см. правило про X.of(context) до первого await).
    final navigator = Navigator.of(context);
    final go = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _InviteSheet(feature: feature),
    );
    if (go == true) {
      await navigator.push(
        MaterialPageRoute(builder: (_) => const AccountScreen()),
      );
    }
  }
}

class _InviteSheet extends StatelessWidget {
  final String feature;
  const _InviteSheet({required this.feature});

  static const _perks = [
    (Icons.track_changes, 'Трекер намазов и серия дней'),
    (Icons.blur_circular, 'Счётчик зикров и обеты'),
    (Icons.monetization_on_outlined, 'Коины и награды у устаза'),
    (Icons.school_outlined, 'Курсы и уроки'),
    (Icons.sensors, 'Прямой эфир и новости'),
  ];

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.7);
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF12211F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Icon(Icons.lock_outline,
                size: 34, color: AppColors.goldLight),
            const SizedBox(height: 12),
            Text(
              '${t('Чтобы открыть')} «$feature»,\n${t('заведите аккаунт')}',
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w700, height: 1.35),
            ),
            const SizedBox(height: 6),
            Text(
              t('Время намаза, Коран, кибла и настройки работают и без него.'),
              style: TextStyle(fontSize: 13, height: 1.4, color: muted),
            ),
            const SizedBox(height: 18),
            for (final (icon, title) in _perks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: AppColors.gold),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(t(title),
                          style: const TextStyle(fontSize: 14.5)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
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
                onPressed: () => Navigator.pop(context, true),
                child: Text(t('Создать аккаунт'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('Позже'), style: TextStyle(color: muted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Заглушка вместо закрытой страницы в свайпах (трекер, зикры, новости).
///
/// Страницы остаются на своих местах, чтобы не переставлять индексы всего
/// PageView; вместо содержимого — замок и приглашение.
class LockedPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const LockedPage({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: GlassCard(
          radius: 24,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Icon(icon, size: 46, color: AppColors.goldLight),
                  const Icon(Icons.lock, size: 20, color: AppColors.gold),
                ],
              ),
              const SizedBox(height: 16),
              Text(t(title),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                t(subtitle),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: const Color(0xFF20180A),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => AccountGate.invite(context, t(title)),
                child: Text(t('Открыть после регистрации'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
