import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/prayer_service.dart';
import '../services/lang.dart';
import '../services/date_fmt.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';

/// Статистика намазов за произвольный период. По умолчанию — с момента
/// создания аккаунта по сегодня.
class PeriodStatsScreen extends StatefulWidget {
  const PeriodStatsScreen({super.key});

  @override
  State<PeriodStatsScreen> createState() => _PeriodStatsScreenState();
}

class _PeriodStatsScreenState extends State<PeriodStatsScreen> {
  late DateTime _from;
  late DateTime _to;
  late DateTime _accountStart;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    final created = state.auth?.current?.createdAt ?? state.now;
    _accountStart = DateTime(created.year, created.month, created.day);
    // Инициализируем один раз.
    if (!_inited) {
      _to = DateTime(state.now.year, state.now.month, state.now.day);
      _from = _accountStart.isAfter(_to) ? _to : _accountStart;
      _inited = true;
    }
  }

  bool _inited = false;

  Future<void> _pick({required bool isFrom}) async {
    final state = AppScope.of(context);
    final today = DateTime(state.now.year, state.now.month, state.now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: _accountStart.isAfter(today) ? today : _accountStart,
      lastDate: today,
      helpText: isFrom ? t('Начало периода') : t('Конец периода'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accentGreen,
            surface: AppColors.skyBottom,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_from.isAfter(_to)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  void _preset(int? days) {
    final state = AppScope.of(context);
    final today = DateTime(state.now.year, state.now.month, state.now.day);
    setState(() {
      _to = today;
      if (days == null) {
        _from = _accountStart.isAfter(today) ? today : _accountStart;
      } else {
        final start = today.subtract(Duration(days: days - 1));
        _from = start.isBefore(_accountStart) ? _accountStart : start;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tracker = state.tracker!;
    final stats = tracker.stats(_from, _to);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Text(t('Статистика за период')),
      ),
      body: DomeBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              // --- Выбор периода ---
              FadeSlideIn(
                child: GlassCard(
                  radius: 20,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _DateField(
                              label: appLang == Lang.ky ? 'Баштап' : 'С',
                              value: fmtDateShort(stats.from),
                              onTap: () => _pick(isFrom: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DateField(
                              label: appLang == Lang.ky ? 'Чейин' : 'По',
                              value: fmtDateShort(stats.to),
                              onTap: () => _pick(isFrom: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          _PresetChip(t('Всё время'), () => _preset(null)),
                          _PresetChip(t('30 дней'), () => _preset(30)),
                          _PresetChip(t('7 дней'), () => _preset(7)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // --- Основные показатели ---
              FadeSlideIn(
                delay: const Duration(milliseconds: 100),
                child: GlassCard(
                  radius: 20,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text('${(stats.readRatio * 100).round()}%',
                              style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.goldLight)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              appLang == Lang.ky
                                  ? '${stats.days} күндө\nнамаз окулду'
                                  : 'намазов прочитано\nза ${stats.days} дн.',
                              style: TextStyle(
                                  fontSize: 14,
                                  height: 1.3,
                                  color: Colors.white
                                      .withValues(alpha: 0.75)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: stats.readRatio,
                          minHeight: 10,
                          backgroundColor:
                              Colors.black.withValues(alpha: 0.3),
                          valueColor: const AlwaysStoppedAnimation(
                              AppColors.accentGreen),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // --- Плитки ---
              FadeSlideIn(
                delay: const Duration(milliseconds: 180),
                child: Row(
                  children: [
                    _StatTile(
                      value: '${stats.read}',
                      label: t('прочитано'),
                      color: AppColors.accentGreen,
                      icon: Icons.check_circle,
                    ),
                    const SizedBox(width: 12),
                    _StatTile(
                      value: '${stats.missed}',
                      label: t('пропущено'),
                      color: Colors.redAccent,
                      icon: Icons.cancel,
                    ),
                    const SizedBox(width: 12),
                    _StatTile(
                      value: '${stats.restored}',
                      label: t('восстановлено'),
                      color: AppColors.goldLight,
                      icon: Icons.history,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 240),
                child: Row(
                  children: [
                    _StatTile(
                      value: '${stats.fullDays}',
                      label: t('полных дней (5/5)'),
                      color: AppColors.gold,
                      icon: Icons.star,
                    ),
                    const SizedBox(width: 12),
                    _StatTile(
                      value: '${stats.days}',
                      label: t('дней в периоде'),
                      color: AppColors.domeLight,
                      icon: Icons.calendar_month,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // --- По намазам ---
              FadeSlideIn(
                delay: const Duration(milliseconds: 300),
                child: Text(t('По намазам'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 340),
                child: GlassCard(
                  radius: 20,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    children: [
                      for (final k in PrayerKey.values
                          .where((k) => k.isPrayer)) ...[
                        _PrayerStatRow(
                          title: k.titleRu,
                          read: stats.readByPrayer[k] ?? 0,
                          total: stats.days,
                        ),
                        if (k != PrayerKey.values.lastWhere((k) => k.isPrayer))
                          const SizedBox(height: 12),
                      ],
                    ],
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

class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _DateField(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.55))),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.event,
                    size: 16, color: AppColors.goldLight),
                const SizedBox(width: 6),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PresetChip(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.domeGreen.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final IconData icon;
  const _StatTile(
      {required this.value,
      required this.label,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassCard(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 10),
            Text(value,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            // Подпись держим в одну строку. Плиток стало три, и «восстановлено»
            // переносилось на второй ряд: у соседних плиток подпись оставалась
            // однострочной, и числа переставали стоять на одном уровне.
            // Уменьшить буквы здесь честнее, чем сокращать слово.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      color: Colors.white.withValues(alpha: 0.7))),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrayerStatRow extends StatelessWidget {
  final String title;
  final int read;
  final int total;
  const _PrayerStatRow(
      {required this.title, required this.read, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : read / total;
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: Colors.black.withValues(alpha: 0.3),
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.accentGreen),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          child: Text('$read/$total',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.75))),
        ),
      ],
    );
  }
}
