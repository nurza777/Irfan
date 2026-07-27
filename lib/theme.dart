import 'package:flutter/material.dart';

/// Цветовая палитра «Ирфан» — по логотипу: глубокий зелёный, золото, крем.
abstract class AppColors {
  static const Color skyTop = Color(0xFF2E5A6B);
  static const Color skyBottom = Color(0xFF1E4D40);
  static const Color domeGreen = Color(0xFF1F6B44);
  static const Color domeDark = Color(0xFF145232);
  static const Color domeLight = Color(0xFF2E8B57);
  static const Color gold = Color(0xFFC9A24B);
  static const Color goldLight = Color(0xFFE0C071);
  static const Color accentGreen = Color(0xFF2FA86C);
  static const Color cream = Color(0xFFF5EFD9);
  static const Color cardGlass = Color(0x66101E18);
  static const Color brick = Color(0xFFD9C9A3);

  // Старая книга (режим «Страница» Корана) — сепия, чернила.
  static const Color paper = Color(0xFFEFE0BE);
  static const Color paperDark = Color(0xFFDFC996);
  static const Color paperEdge = Color(0xFFB2925A);
  static const Color ink = Color(0xFF3A2A17);
  static const Color inkSoft = Color(0xFF6E5836);
}

ThemeData buildIrfanTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.domeGreen,
      brightness: Brightness.dark,
      primary: AppColors.accentGreen,
      secondary: AppColors.gold,
    ),
    scaffoldBackgroundColor: AppColors.skyBottom,
    fontFamily: 'Roboto',
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
  );
}
