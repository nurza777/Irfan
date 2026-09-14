import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/books_service.dart';
import '../services/lang.dart';
import '../theme.dart';

/// Чтение скачанной книги. Открывается на той странице, где остановились.
class BookReaderScreen extends StatefulWidget {
  final Book book;
  const BookReaderScreen({super.key, required this.book});

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  static const _ground = Color(0xFF12211F);

  final _controller = PdfViewerController();
  String? _path;
  int _initial = 1;
  int _page = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final svc = BooksService.instance;
    final path = await svc.localPath(widget.book);
    final page = await svc.lastPage(widget.book);
    if (!mounted) return;
    setState(() {
      _path = path;
      _initial = page;
      _page = page;
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    return Scaffold(
      backgroundColor: _ground,
      appBar: AppBar(
        backgroundColor: _ground,
        title: Text(widget.book.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_total > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('$_page / $_total',
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.goldLight)),
              ),
            ),
        ],
      ),
      body: path == null
          ? const Center(child: CircularProgressIndicator())
          : PdfViewer.file(
              path,
              controller: _controller,
              initialPageNumber: _initial,
              params: PdfViewerParams(
                backgroundColor: _ground,
                onViewerReady: (document, controller) {
                  if (mounted) setState(() => _total = document.pages.length);
                },
                onPageChanged: (n) {
                  if (n == null || !mounted) return;
                  setState(() => _page = n);
                  // Сохраняем на каждой смене страницы, а не при выходе:
                  // приложение могут выгрузить из памяти прямо посреди
                  // чтения, и «выхода» просто не случится.
                  BooksService.instance.savePage(widget.book, n);
                },
                errorBannerBuilder: (context, error, stackTrace, ref) =>
                    Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(t('Не удалось открыть книгу'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.textSoft)),
                  ),
                ),
              ),
            ),
    );
  }
}
