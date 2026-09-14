import 'package:flutter/material.dart';

import '../services/api_config.dart';
import '../services/books_service.dart';
import '../services/lang.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import 'book_reader_screen.dart';

/// Раздел «Книги»: список из каталога, скачивание и переход к чтению.
///
/// Открыт и без регистрации: книги работают на самом телефоне, аккаунт им
/// не нужен (тот же принцип, что у Корана и азкаров).
class BooksScreen extends StatefulWidget {
  const BooksScreen({super.key});

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  final _svc = BooksService.instance;
  List<Book>? _books;
  bool _offline = false;
  String _base = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final base = await ApiConfig.base();
    final cached = await _svc.cached();
    if (!mounted) return;
    setState(() {
      _base = base;
      _books ??= cached;
    });
    if (cached != null) await _svc.refreshDownloaded(cached);
    await _refresh();
  }

  Future<void> _refresh() async {
    final fresh = await _svc.fetch();
    if (!mounted) return;
    setState(() {
      _offline = fresh == null;
      if (fresh != null) _books = fresh;
    });
  }

  /// Тап: скачанную — открыть, нескачанную — скачать. Открывать сразу после
  /// скачивания не станем: человек мог нажать «на потом», а уже листает
  /// дальше по списку.
  Future<void> _tap(Book b) async {
    if (_svc.progress.containsKey(b.id)) return;
    if (_svc.downloaded.contains(b.id)) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => BookReaderScreen(book: b)));
      return;
    }
    final ok = await _svc.download(b);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('Не удалось скачать книгу — проверьте связь'))));
    }
  }

  Future<void> _remove(Book b) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Удалить с телефона?')),
        content:
            Text(t('Книга останется в списке — скачать её можно будет снова.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Отмена'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Удалить'))),
        ],
      ),
    );
    if (yes == true) await _svc.delete(b);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + kToolbarHeight + 8;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Text(t('Книги')),
      ),
      body: DomeBackground(
        child: RefreshIndicator(
          onRefresh: _refresh,
          edgeOffset: top,
          child: _body(top),
        ),
      ),
    );
  }

  Widget _body(double top) {
    final books = _books;
    // Прокручиваемый даже в пустом состоянии: иначе «потянуть, чтобы
    // обновить» не срабатывает, а без связи это единственная кнопка.
    Widget message(String text) => ListView(
          padding: EdgeInsets.fromLTRB(32, top + 80, 32, 32),
          children: [
            const Icon(Icons.local_library_outlined,
                size: 48, color: AppColors.goldLight),
            const SizedBox(height: 14),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, height: 1.4, color: AppColors.textSoft)),
          ],
        );

    if (books == null) {
      return _offline
          ? message(t('Нет связи с сервером'))
          : const Center(child: CircularProgressIndicator());
    }
    if (books.isEmpty) return message(t('Книги скоро появятся'));

    return ListView(
      padding: EdgeInsets.fromLTRB(16, top, 16, 24),
      children: [
        if (_offline)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(t('Нет связи — показан сохранённый список'),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, color: AppColors.textFaint)),
          ),
        for (final b in books) _tile(b),
      ],
    );
  }

  Widget _tile(Book b) {
    return AnimatedBuilder(
      animation: _svc,
      builder: (context, _) {
        final p = _svc.progress[b.id];
        final have = _svc.downloaded.contains(b.id);
        final meta = [
          if (b.size >= 1048576)
            '${(b.size / 1048576).toStringAsFixed(1)} МБ'
          else if (b.size > 0)
            '${(b.size / 1024).ceil()} КБ',
          if (b.lang == 'ru') t('на русском'),
          if (b.lang == 'ky') t('на кыргызском'),
          if (have) t('Скачано'),
        ].join(' · ');
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _tap(b),
            onLongPress: have ? () => _remove(b) : null,
            child: GlassCard(
              radius: 16,
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cover(b),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.title,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        if (b.author.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(b.author,
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.goldLight)),
                        ],
                        if (b.description.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(b.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: AppColors.textSoft)),
                        ],
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(meta,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textFaint)),
                        ],
                        if (p != null) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                              value: p > 0 ? p : null,
                              color: AppColors.gold,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.12)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    have
                        ? Icons.chevron_right
                        : (p != null
                            ? Icons.downloading
                            : Icons.download_outlined),
                    color: have ? Colors.white54 : AppColors.gold,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cover(Book b) {
    final placeholder = Container(
      color: AppColors.domeGreen.withValues(alpha: 0.5),
      child: const Icon(Icons.menu_book, color: AppColors.goldLight),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 54,
        height: 76,
        child: b.cover.isEmpty || _base.isEmpty
            ? placeholder
            : Image.network('$_base/uploads/${b.cover}',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder),
      ),
    );
  }
}
