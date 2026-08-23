import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;

import '../app_state.dart';
import '../services/quran_service.dart';
import '../services/lang.dart';
import '../services/surah_names.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';
import 'surah_screen.dart';

/// Закладки и заметки: две вкладки со списками аятов.
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final qs = AppScope.of(context).quran!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(t('Закладки и заметки')),
          centerTitle: true,
          bottom: TabBar(
            indicatorColor: AppColors.gold,
            labelColor: AppColors.goldLight,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(
                  text: t('Закладки'),
                  icon: const Icon(Icons.bookmark, size: 20)),
              Tab(
                  text: t('Заметки'),
                  icon: const Icon(Icons.sticky_note_2, size: 20)),
            ],
          ),
        ),
        body: DomeBackground(
          child: AnimatedBuilder(
            animation: qs,
            builder: (context, _) => TabBarView(
              children: [
                _List(
                  keys: qs.bookmarks,
                  qs: qs,
                  emptyIcon: Icons.bookmark_border,
                  emptyText:
                      'Закладок пока нет.\nОтметьте аят закладкой при чтении.',
                ),
                _List(
                  keys: qs.notedVerses,
                  qs: qs,
                  showNote: true,
                  emptyIcon: Icons.note_add_outlined,
                  emptyText:
                      'Заметок пока нет.\nДобавьте заметку к аяту при чтении.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  final List<String> keys;
  final QuranService qs;
  final bool showNote;
  final IconData emptyIcon;
  final String emptyText;
  const _List({
    required this.keys,
    required this.qs,
    this.showNote = false,
    required this.emptyIcon,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    if (keys.isEmpty) {
      return Center(
        child: FadeSlideIn(
          child: GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(emptyIcon,
                    size: 40, color: Colors.white.withValues(alpha: 0.7)),
                const SizedBox(height: 12),
                Text(t(emptyText),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 112, 16, 16),
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final parts = keys[i].split(':').map(int.parse).toList();
        final surah = parts[0];
        final verse = parts[1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FadeSlideIn(
            delay: Duration(milliseconds: 40 * i),
            child: GlassCard(
              radius: 16,
              padding: const EdgeInsets.all(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SurahScreen(surah: surah, scrollToVerse: verse),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                AppColors.domeGreen.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.gold
                                    .withValues(alpha: 0.5)),
                          ),
                          child: Text('$surah:$verse',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.goldLight)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(surahName(surah),
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => showNote
                              ? qs.setNote(surah, verse, '')
                              : qs.toggleBookmark(surah, verse),
                          icon: Icon(
                              showNote
                                  ? Icons.delete_outline
                                  : Icons.bookmark_remove,
                              size: 20,
                              color: Colors.redAccent
                                  .withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      quran.getVerse(surah, verse),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, height: 1.8),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      // Через сервис, а не из пакета `quran` напрямую: тот
                      // отдаёт Кулиева, права на которого не подтверждены, и
                      // закладки оказывались единственным местом, где он
                      // всё ещё показывался.
                      qs.translationOf(surah, verse),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.8)),
                    ),
                    if (showNote) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: const Border(
                              left: BorderSide(
                                  color: AppColors.gold, width: 3)),
                        ),
                        child: Text(qs.noteOf(surah, verse) ?? '',
                            style: const TextStyle(
                                fontSize: 14, height: 1.4)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
