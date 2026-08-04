import 'package:flutter/material.dart';

import '../../services/staff_api.dart';
import '../../widgets/glass.dart';
import '../../services/staff_auth.dart';
import '../../theme.dart';

/// Редактор азкаров и дуа: устаз набирает арабский текст с транслитерацией и
/// смыслом, админ одобряет — после чего они появляются у студентов рядом со
/// встроенным набором.
///
/// Так арабский добавляют люди, а не разработчик: встроенные азкары брались
/// только из пакета Корана и уже выверенных строк, вручную ничего не набиралось.
class AzkarTab extends StatefulWidget {
  const AzkarTab({super.key});

  @override
  State<AzkarTab> createState() => _AzkarTabState();
}

class _AzkarTabState extends State<AzkarTab> {
  final StaffApi _api = const StaffApi();
  List<AzkarCategoryDto> _cats = [];
  PendingAzkar? _pending;
  bool _loading = true;
  bool _busy = false;

  bool get _isAdmin => false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cats = await _api.fetchAzkar();
    final pending = await _api.fetchPendingAzkar();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _pending = pending;
      _loading = false;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _publish() async {
    if (_cats.isEmpty) {
      _snack('Добавьте хотя бы одну категорию');
      return;
    }
    final empty = _cats.where((c) => c.items.isEmpty).toList();
    if (empty.isNotEmpty) {
      _snack('В категории «${empty.first.title}» нет ни одного зикра');
      return;
    }
    setState(() => _busy = true);
    final author = StaffAuth.instance.session?.name ?? 'Устаз';
    // Ученикам публикует только админ (в веб-панели) — отсюда уходит заявка.
    final err = await _api.submitAzkar(_cats, author);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(err ?? 'Отправлено на модерацию');
    if (err == null) _load();
  }

  Future<void> _editCategory({AzkarCategoryDto? cat, int? index}) async {
    final title = TextEditingController(text: cat?.title ?? '');
    final subtitle = TextEditingController(text: cat?.subtitle ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.skyBottom,
        title: Text(cat == null ? 'Новая категория' : 'Категория'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(
                  labelText: 'Название', hintText: 'Например: Дуа перед сном'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: subtitle,
              decoration: const InputDecoration(labelText: 'Подпись'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить')),
        ],
      ),
    );
    final titleText = title.text.trim();
    final subtitleText = subtitle.text.trim();
    title.dispose();
    subtitle.dispose();
    if (!mounted || ok != true || titleText.isEmpty) return;
    setState(() {
      final updated = AzkarCategoryDto(
        title: titleText,
        subtitle: subtitleText,
        items: cat?.items ?? [],
      );
      if (index == null) {
        _cats.add(updated);
      } else {
        _cats[index] = updated;
      }
    });
  }

  Future<void> _editItem(int catIndex, {AzkarItem? item, int? index}) async {
    final arabic = TextEditingController(text: item?.arabic ?? '');
    final translit = TextEditingController(text: item?.translit ?? '');
    final meaning = TextEditingController(text: item?.meaning ?? '');
    final source = TextEditingController(text: item?.source ?? '');
    final count = TextEditingController(text: '${item?.count ?? 1}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.skyBottom,
        title: Text(item == null ? 'Новый зикр' : 'Зикр'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: arabic,
                maxLines: 4,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontSize: 20, height: 1.8),
                decoration: const InputDecoration(
                    labelText: 'Арабский текст',
                    alignLabelWithHint: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: translit,
                decoration:
                    const InputDecoration(labelText: 'Транслитерация'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: meaning,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Смысл'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: source,
                decoration: const InputDecoration(
                    labelText: 'Источник',
                    hintText: 'Например: Бухари 6306'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: count,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Сколько раз читать'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить')),
        ],
      ),
    );
    // Снимаем значения и освобождаем поля до любых выходов из метода.
    final arabicText = arabic.text.trim();
    final translitText = translit.text.trim();
    final meaningText = meaning.text.trim();
    final sourceText = source.text.trim();
    final countValue = int.tryParse(count.text.trim())?.clamp(1, 1000) ?? 1;
    for (final c in [arabic, translit, meaning, source, count]) {
      c.dispose();
    }

    if (!mounted || ok != true) return;
    if (arabicText.isEmpty) {
      _snack('Арабский текст обязателен');
      return;
    }
    setState(() {
      final updated = AzkarItem(
        arabic: arabicText,
        translit: translitText,
        meaning: meaningText,
        source: sourceText,
        count: countValue,
      );
      final items = _cats[catIndex].items;
      if (index == null) {
        items.add(updated);
      } else {
        items[index] = updated;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.gold));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Азкары и дуа',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Добавить категорию',
                onPressed: () => _editCategory(),
                icon: const Icon(Icons.add_circle_outline,
                    color: AppColors.gold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Студенты увидят их рядом со встроенным набором. '
            'Арабский текст проверяйте перед отправкой.',
            style: TextStyle(
                fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
          ),
          if (_pending != null && !_isAdmin) ...[
            const SizedBox(height: 12),
            _StatusBanner(pending: _pending!),
          ],
          const SizedBox(height: 14),
          if (_cats.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Text('Пока ничего не добавлено',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5))),
            ),
          for (final (ci, c) in _cats.indexed) ...[
            GlassCard(
              radius: 18,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.title,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700)),
                            if (c.subtitle.isNotEmpty)
                              Text(c.subtitle,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white
                                          .withValues(alpha: 0.6))),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            _editCategory(cat: c, index: ci),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
                      IconButton(
                        onPressed: () =>
                            setState(() => _cats.removeAt(ci)),
                        icon: const Icon(Icons.delete_outline,
                            size: 20, color: Colors.redAccent),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  for (final (ii, it) in c.items.indexed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(it.arabic,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                              fontFamily: 'AmiriQuran', fontSize: 18)),
                      subtitle: Text(
                          '${it.translit.isEmpty ? it.meaning : it.translit}'
                          ' · ${it.count}×',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () =>
                                _editItem(ci, item: it, index: ii),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                          IconButton(
                            onPressed: () =>
                                setState(() => c.items.removeAt(ii)),
                            icon: const Icon(Icons.close,
                                size: 18, color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                  TextButton.icon(
                    onPressed: () => _editItem(ci),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Добавить зикр'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentGreen,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _busy ? null : _publish,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(_isAdmin ? 'Опубликовать' : 'На модерацию'),
          ),
        ],
      ),
    );
  }
}

/// Статус последней заявки — чтобы устаз видел решение админа.
class _StatusBanner extends StatelessWidget {
  final PendingAzkar pending;
  const _StatusBanner({required this.pending});

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (pending.status) {
      ModerationStatus.pending => ('На модерации у администратора',
          AppColors.gold),
      ModerationStatus.approved => ('Одобрено и опубликовано',
          AppColors.accentGreen),
      ModerationStatus.rejected => (
          'Отклонено${pending.reason.isEmpty ? '' : ': ${pending.reason}'}',
          Colors.redAccent
        ),
      _ => ('', Colors.transparent),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, color: color))),
        ],
      ),
    );
  }
}
