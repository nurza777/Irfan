import 'package:flutter/material.dart';

import '../theme.dart';

/// Раздел «Курсы» — пока каталог-заглушка, наполним содержимым позже.
class CoursesPage extends StatelessWidget {
  const CoursesPage({super.key});

  static const _courses = [
    ('Основы намаза', 'Как правильно совершать пять намазов', Icons.mosque),
    ('Таджвид', 'Правила чтения Корана', Icons.menu_book),
    ('Арабский алфавит', 'Учимся читать с нуля', Icons.abc),
    ('Жизнь Пророка ﷺ', 'Сира — история жизни', Icons.history_edu),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.skyBottom,
      appBar: AppBar(
        backgroundColor: AppColors.domeDark,
        title: const Text('Курсы'),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _courses.length,
        itemBuilder: (context, i) {
          final (title, subtitle, icon) = _courses[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: AppColors.cardGlass,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.domeGreen.withValues(alpha: 0.5),
                        border:
                            Border.all(color: AppColors.gold, width: 1),
                      ),
                      child:
                          Icon(icon, color: AppColors.cream, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                          Text(subtitle,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white
                                      .withValues(alpha: 0.7))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: AppColors.gold.withValues(alpha: 0.25),
                      ),
                      child: const Text('Скоро',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.goldLight)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
