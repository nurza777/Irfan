import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/zikr_service.dart';
import '../services/lang.dart';
import '../theme.dart';

/// Настройки зикров: какие зикры и сколько раз в день. Изменения
/// сохраняются сразу.
Future<void> showZikrSettings(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _ZikrSettingsSheet(),
  );
}

class _ZikrSettingsSheet extends StatefulWidget {
  const _ZikrSettingsSheet();

  @override
  State<_ZikrSettingsSheet> createState() => _ZikrSettingsSheetState();
}

class _ZikrSettingsSheetState extends State<_ZikrSettingsSheet> {
  final _nameCtrl = TextEditingController();
  final _targetCtrl = TextEditingController(text: '33');

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _setTarget(AppState state, ZikrGoal g, int delta) async {
    final goals = state.zikrs!.goals;
    final i = goals.indexWhere((x) => x.id == g.id);
    if (i < 0) return;
    final next = (g.target + delta).clamp(1, 9999);
    goals[i] = g.copyWith(target: next);
    await state.saveZikrGoals(goals);
    setState(() {});
  }

  Future<void> _remove(AppState state, ZikrGoal g) async {
    final goals = state.zikrs!.goals..removeWhere((x) => x.id == g.id);
    await state.saveZikrGoals(goals);
    setState(() {});
  }

  Future<void> _addPreset(AppState state, ZikrGoal preset) async {
    final goals = state.zikrs!.goals;
    if (goals.any((g) => g.id == preset.id)) return;
    goals.add(preset);
    await state.saveZikrGoals(goals);
    setState(() {});
  }

  Future<void> _addCustom(AppState state) async {
    final name = _nameCtrl.text.trim();
    final target = int.tryParse(_targetCtrl.text.trim()) ?? 0;
    if (name.isEmpty || target < 1) return;
    final goals = state.zikrs!.goals;
    goals.add(ZikrGoal(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      title: name,
      target: target,
    ));
    await state.saveZikrGoals(goals);
    if (!mounted) return;
    _nameCtrl.clear();
    FocusScope.of(context).unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final goals = state.zikrs!.goals;
    final availablePresets = ZikrService.presets
        .where((p) => goals.every((g) => g.id != p.id))
        .toList();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          color: AppColors.skyBottom.withValues(alpha: 0.88),
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight:
                      MediaQuery.of(context).size.height * 0.8),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                    Text(t('Настройки зикров'),
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    Text(t('Какие зикры и сколько раз в день'),
                        style: TextStyle(
                            fontSize: 14,
                            color:
                                Colors.white.withValues(alpha: 0.7))),
                    const SizedBox(height: 14),
                    for (final g in goals)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color:
                                Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.white
                                    .withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(g.title,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight:
                                                FontWeight.w600)),
                                    if (g.arabic.isNotEmpty)
                                      Text(g.arabic,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: AppColors
                                                  .goldLight)),
                                  ],
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: g.target > 1
                                    ? () => _setTarget(state, g, -1)
                                    : null,
                                icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.white70),
                              ),
                              SizedBox(
                                width: 40,
                                child: Text('${g.target}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.goldLight)),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    _setTarget(state, g, 1),
                                icon: const Icon(
                                    Icons.add_circle_outline,
                                    color: Colors.white70),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _remove(state, g),
                                icon: Icon(Icons.delete_outline,
                                    color: Colors.redAccent
                                        .withValues(alpha: 0.8)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (availablePresets.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(t('Добавить из каталога'),
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.white
                                  .withValues(alpha: 0.7))),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in availablePresets)
                            ActionChip(
                              backgroundColor:
                                  Colors.black.withValues(alpha: 0.3),
                              side: const BorderSide(
                                  color: AppColors.gold, width: 1),
                              label: Text('${p.title} · ${p.target}',
                                  style: const TextStyle(
                                      color: AppColors.cream,
                                      fontSize: 13)),
                              onPressed: () => _addPreset(state, p),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(t('Свой зикр'),
                        style: TextStyle(
                            fontSize: 14,
                            color:
                                Colors.white.withValues(alpha: 0.7))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _nameCtrl,
                            style: const TextStyle(fontSize: 15),
                            decoration: _dec('Название'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _targetCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 15),
                            decoration: _dec(t('Раз')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(
                              backgroundColor: AppColors.accentGreen),
                          onPressed: () => _addCustom(state),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: t(label),
        isDense: true,
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.3),
        labelStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      );
}
