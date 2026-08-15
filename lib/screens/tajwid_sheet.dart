
import 'package:flutter/material.dart';

import '../services/tajwid.dart';
import '../services/lang.dart';
import '../theme.dart';
import '../widgets/glass.dart';

/// Легенда правил таджвида: список правил с цветом; тап — пояснение.
Future<void> showTajwidLegend(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _TajwidLegend(),
  );
}

class _TajwidLegend extends StatelessWidget {
  const _TajwidLegend();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: MaybeBlur(
        child: Container(
          color: AppColors.skyBottom.withValues(alpha: sheetAlpha(0.9)),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(t('Правила таджвида'),
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  Text(t('Нажмите на правило, чтобы прочитать пояснение'),
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.65))),
                  const SizedBox(height: 12),
                  for (final rule in TajwidRule.values)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: rule.color,
                          boxShadow: [
                            BoxShadow(
                                color: rule.color.withValues(alpha: 0.5),
                                blurRadius: 8),
                          ],
                        ),
                      ),
                      title: Text(t(rule.titleRu),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      trailing: Icon(Icons.chevron_right,
                          color: Colors.white.withValues(alpha: 0.4)),
                      onTap: () => _showRule(context, rule),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    t('Подсветка — ориентир для чтения и не заменяет обучение '
                        'у преподавателя.'),
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showRule(BuildContext context, TajwidRule rule) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ClipRRect(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        child: MaybeBlur(
          child: Container(
            color: AppColors.skyBottom.withValues(alpha: sheetAlpha(0.92)),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: rule.color),
                        ),
                        const SizedBox(width: 10),
                        Text(t(rule.titleRu),
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(t(rule.description),
                        style: const TextStyle(fontSize: 15, height: 1.5)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
