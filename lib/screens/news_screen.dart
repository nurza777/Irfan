import 'package:flutter/material.dart';

import '../services/news_service.dart';
import '../services/lang.dart';
import '../services/date_fmt.dart';
import '../theme.dart';
import '../widgets/dome_background.dart';
import '../widgets/glass.dart';

/// Новости от устаза.
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  late Future<List<NewsItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = NewsService.fetch();
  }

  Future<void> _refresh() async {
    final f = NewsService.fetch();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Text(t('Новости')),
      ),
      body: DomeBackground(
        child: SafeArea(
          child: FutureBuilder<List<NewsItem>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.gold));
              }
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return _Empty(onRefresh: _refresh);
              }
              return RefreshIndicator(
                color: AppColors.gold,
                backgroundColor: AppColors.skyBottom,
                onRefresh: _refresh,
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                      16, MediaQuery.of(context).padding.top + 60, 16, 24),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _NewsCard(item: items[i]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Новости как страница свайпа (справа от зикров), без своего Scaffold —
/// живёт внутри общего DomeBackground корневого экрана.
class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  late Future<List<NewsItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = NewsService.fetch();
  }

  Future<void> _refresh() async {
    final f = NewsService.fetch();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            FadeSlideIn(
              offset: const Offset(24, 0),
              child: Row(
                children: [
                  Text(t('Новости'),
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  PressableScale(
                    onTap: _refresh,
                    child: const GlassCard(
                      radius: 22,
                      blur: 10,
                      darkness: 0.18,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.refresh, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: FutureBuilder<List<NewsItem>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.gold));
                  }
                  final items = snap.data ?? [];
                  if (items.isEmpty) return _Empty(onRefresh: _refresh);
                  return RefreshIndicator(
                    color: AppColors.gold,
                    backgroundColor: AppColors.skyBottom,
                    onRefresh: _refresh,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: items.length,
                      itemBuilder: (context, i) =>
                          _NewsCard(item: items[i]),
                    ),
                  );
                },
              ),
            ),
            Center(
              child: Text(t('Свайп вправо — назад к зикрам'),
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.55))),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final NewsItem item;
  const _NewsCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FadeSlideIn(
        child: GlassCard(
          radius: 18,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.campaign_outlined,
                      size: 18, color: AppColors.goldLight),
                  const SizedBox(width: 8),
                  if (item.date != null)
                    Text(
                      fmtDateLong(item.date!),
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6)),
                    ),
                ],
              ),
              if (item.title.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(item.title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
              ],
              if (item.body.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.body,
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.85))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _Empty({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.skyBottom,
      onRefresh: onRefresh,
      child: ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          Center(
            child: Column(
              children: [
                Icon(Icons.campaign_outlined,
                    size: 54, color: Colors.white.withValues(alpha: 0.4)),
                const SizedBox(height: 14),
                Text(t('Пока новостей нет'),
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(t('Потяните вниз, чтобы обновить'),
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
