import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF0066FF);
  static const primaryDark = Color(0xFF0052CC);
  static const primaryLight = Color(0xFFE8F0FE);

  static const bgSidebar = Color(0xFF2E2E2E);
  static const bgPanel = Color(0xFFF7F7F7);
  static const bgContent = Color(0xFFF0EDE8);
  static const bgWhite = Colors.white;

  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF888888);
  static const textLight = Color(0xFFB2B2B2);

  static const bubbleSelf = Color(0xFF5B9EF4);
  static const bubbleOther = Colors.white;

  static const danger = Color(0xFFFA5151);
  static const warning = Color(0xFFFF9800);

  static const divider = Color(0xFFE5E5E5);
  static const border = Color(0xFFE5E5E5);

  static const List<Color> avatarColors = [
    Color(0xFF1abc9c), Color(0xFF2ecc71), Color(0xFF3498db),
    Color(0xFF9b59b6), Color(0xFFe74c3c), Color(0xFFe67e22),
    Color(0xFFf39c12), Color(0xFF16a085), Color(0xFF27ae60),
    Color(0xFF2980b9), Color(0xFF8e44ad), Color(0xFFc0392b),
  ];
}

class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
    ),
    scaffoldBackgroundColor: AppColors.bgPanel,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgPanel,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 0.5, space: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
