import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../widgets/dome_background.dart';
import 'home_page.dart';
import 'quran_page.dart';
import 'tracker_page.dart';

/// Корневой экран: свайпы влево/вправо листают Трекер ← Главная → Коран
/// с эффектом перелистывания страницы книги.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final _controller = PageController(initialPage: 1);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) => _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );

  Widget _flipPage(int index, Widget child) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        double page = 1;
        if (_controller.hasClients && _controller.position.haveDimensions) {
          page = _controller.page ?? 1;
        }
        final delta = (index - page).clamp(-1.0, 1.0);
        if (delta == 0) return child;
        // Поворот вокруг ближнего к центру края — как страница книги.
        final angle = delta * -math.pi / 2.5;
        return Transform(
          alignment:
              delta > 0 ? Alignment.centerLeft : Alignment.centerRight,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          child: Opacity(
            opacity: (1 - delta.abs() * 0.4).clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.ready) {
      return const Scaffold(
        body: DomeBackground(
          child: Center(
              child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      body: DomeBackground(
        child: PageView(
          controller: _controller,
          children: [
            _flipPage(0, const TrackerPage()),
            _flipPage(
              1,
              HomePage(
                onOpenTracker: () => _goTo(0),
                onOpenQuran: () => _goTo(2),
              ),
            ),
            _flipPage(2, const QuranPage()),
          ],
        ),
      ),
    );
  }
}
