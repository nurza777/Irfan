import 'package:flutter/material.dart';

import '../../services/staff_auth.dart';
import '../../theme.dart';
import '../../widgets/dome_background.dart';
import '../../widgets/glass.dart';
import 'azkar_tab.dart';
import 'courses_tab.dart';
import 'live_tab.dart';
import 'news_tab.dart';
import 'staff_login_screen.dart';

/// Кабинет устаза внутри приложения учеников.
///
/// Раньше это было отдельное приложение «Ирфан Устаз». Слито в одно, потому
/// что приложение только для персонала в App Store не проходит (нет функций
/// для обычного пользователя), а держать две сборки ради четырёх экранов
/// дороже, чем разделить их ролью.
class StaffHome extends StatefulWidget {
  /// С какой вкладки открыть. Нужен отладочному хуку: в симуляторе нечем
  /// нажимать, а проверять надо каждую.
  final int initialTab;

  const StaffHome({super.key, this.initialTab = 0});

  /// Открывает кабинет: вошедшему — сразу вкладки, остальным — экран входа.
  static Future<void> open(BuildContext context, {int initialTab = 0}) async {
    final auth = StaffAuth.instance;
    await auth.init();
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => auth.isStaff
          ? StaffHome(initialTab: initialTab)
          : const StaffLoginScreen(),
    ));
  }

  @override
  State<StaffHome> createState() => _StaffHomeState();
}

class _StaffHomeState extends State<StaffHome> {
  late int _tab = widget.initialTab;

  static const _tabs = <(IconData, String)>[
    (Icons.sensors, 'Эфир'),
    (Icons.school_outlined, 'Курсы'),
    (Icons.campaign_outlined, 'Новости'),
    (Icons.auto_awesome_outlined, 'Азкары'),
  ];

  @override
  void initState() {
    super.initState();
    // Учётку могли отключить, пока приложение лежало в фоне.
    StaffAuth.instance.addListener(_onAuthChanged);
    StaffAuth.instance.refresh();
  }

  @override
  void dispose() {
    StaffAuth.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted || StaffAuth.instance.isStaff) return;
    // Messenger берём ДО закрытия экрана: после pop этот context уже не
    // в дереве, и обращение к нему бросило бы исключение вместо сообщения.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(const SnackBar(
        content: Text('Вход в кабинет закрыт администратором')));
  }

  Future<void> _logout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.domeDark,
        title: const Text('Выйти из кабинета?'),
        content: const Text('Вы останетесь в приложении как обычный '
            'пользователь. Чтобы вернуться в кабинет, понадобится логин '
            'и пароль.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Выйти')),
        ],
      ),
    );
    if (yes != true) return;
    await StaffAuth.instance.logout();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final name = StaffAuth.instance.session?.name ?? 'Устаз';
    return Scaffold(
      body: DomeBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back,
                          color: AppColors.cream),
                      tooltip: 'К приложению',
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Кабинет устаза',
                              style: TextStyle(
                                  color: AppColors.cream,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textFaint, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout, color: AppColors.textSoft),
                      tooltip: 'Выйти из кабинета',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: const [
                    LiveTab(),
                    CoursesTab(),
                    NewsTab(),
                    AzkarTab(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: GlassCard(
                  radius: 28,
                  blur: 14,
                  darkness: 0.3,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      for (final (i, t) in _tabs.indexed)
                        Expanded(
                          child: PressableScale(
                            onTap: () => setState(() => _tab = i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 9, horizontal: 2),
                              decoration: BoxDecoration(
                                color: _tab == i
                                    ? AppColors.domeGreen
                                        .withValues(alpha: 0.55)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: _tab == i
                                        ? AppColors.gold
                                        : Colors.transparent),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(t.$1,
                                      size: 22,
                                      color: _tab == i
                                          ? AppColors.cream
                                          : Colors.white
                                              .withValues(alpha: 0.6)),
                                  const SizedBox(height: 2),
                                  Text(t.$2,
                                      maxLines: 1,
                                      softWrap: false,
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: _tab == i
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: _tab == i
                                              ? AppColors.cream
                                              : Colors.white
                                                  .withValues(alpha: 0.6))),
                                ],
                              ),
                            ),
                          ),
                        ),
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
