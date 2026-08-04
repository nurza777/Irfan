import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/staff_api.dart';
import '../../widgets/glass.dart';
import '../../services/staff_auth.dart';
import '../../theme.dart';

/// Новости устаза: создание, редактирование и публикация объявлений
/// (news.json) для студентов.
class NewsTab extends StatefulWidget {
  const NewsTab({super.key});

  @override
  State<NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<NewsTab> {
  List<NewsPost> _items = [];
  bool _loading = true;
  bool _publishing = false;
  bool _dirty = false;

  bool get _isAdmin => false;
  StaffApi get _api => const StaffApi();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _api.fetchNews();
    if (!mounted) return;
    setState(() {
      _items = list..sort((a, b) => b.date.compareTo(a.date));
      _loading = false;
      _dirty = false;
    });
  }

  Future<void> _publish() async {
    final author = StaffAuth.instance.session?.name ?? 'Устаз';
    setState(() => _publishing = true);
    // Ученикам публикует только админ (в веб-панели) — отсюда уходит заявка.
    final err = await _api.submitNews(_items, author);
    if (!mounted) return;
    setState(() => _publishing = false);
    if (err == null) {
      setState(() => _dirty = false);
      _snack('Отправлено администратору на модерацию');
    } else {
      _snack(err);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Future<void> _edit([NewsPost? post]) async {
    final titleCtrl = TextEditingController(text: post?.title ?? '');
    final bodyCtrl = TextEditingController(text: post?.body ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.skyBottom,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 18,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(post == null ? 'Новая новость' : 'Редактировать',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 15),
              decoration: _dec('Заголовок'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyCtrl,
              maxLines: 5,
              style: const TextStyle(fontSize: 15),
              decoration: _dec('Текст новости'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Сохранить'),
              ),
            ),
          ],
        ),
      ),
    );
    // Значения снимаем сразу, а поля освобождаем: контроллер живёт до конца
    // метода, и без dispose каждое открытие формы оставляло бы его в памяти.
    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    titleCtrl.dispose();
    bodyCtrl.dispose();

    // Экран могли закрыть, пока форма была открыта.
    if (!mounted || saved != true) return;
    if (title.isEmpty && body.isEmpty) return;
    setState(() {
      if (post == null) {
        _items.insert(
            0, NewsPost(title: title, body: body, date: DateTime.now()));
      } else {
        post.title = title;
        post.body = body;
      }
      _dirty = true;
    });
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.3),
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
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

  void _delete(NewsPost post) {
    setState(() {
      _items.remove(post);
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final author = StaffAuth.instance.session?.name ?? 'Устаз';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Row(
            children: [
              const Text('Новости',
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh, color: AppColors.gold),
                tooltip: 'Загрузить с сервера',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Публикуются от имени: $author',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.6))),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.gold))
              : _items.isEmpty
                  ? _empty()
                  : ListView.builder(
                      padding:
                          const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      itemCount: _items.length,
                      itemBuilder: (_, i) => _card(_items[i]),
                    ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.gold),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Добавить'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _dirty
                        ? AppColors.accentGreen
                        : AppColors.accentGreen.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _publishing ? null : _publish,
                  icon: _publishing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Icon(
                          _isAdmin
                              ? Icons.cloud_upload_outlined
                              : Icons.send_outlined,
                          size: 20),
                  label: Text(_isAdmin ? 'Опубликовать' : 'На модерацию'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined,
                size: 52, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('Пока нет новостей',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Нажмите «+», чтобы добавить',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.6))),
          ],
        ),
      );

  Widget _card(NewsPost post) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(DateFormat('d MMMM yyyy', 'ru').format(post.date),
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.55))),
                  if (post.title.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(post.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                  if (post.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(post.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.8))),
                  ],
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _edit(post),
                  icon: const Icon(Icons.edit,
                      size: 20, color: AppColors.goldLight),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _delete(post),
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: Colors.red.shade300),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
