import 'package:flutter/material.dart';

/// Theme cho người khiếm thị:
/// - Font >= 24sp
/// - Contrast ratio >= 7:1
/// - Màu sắc high contrast
class AppTheme {
  AppTheme._();

  // High contrast colors
  static const Color primaryDark = Color(0xFF0D1B2A);    // Navy đậm
  static const Color surface = Color(0xFF1B2838);         // Background
  static const Color onSurface = Color(0xFFFFFFFF);       // White text
  static const Color warning = Color(0xFFFF6B35);         // Cam cảnh báo
  static const Color warningMedium = Color(0xFFFFA000);   // Vàng cam - medium warning
  static const Color danger = Color(0xFFFF0000);          // Đỏ khẩn cấp
  static const Color safe = Color(0xFF00E676);            // Xanh an toàn
  static const Color accent = Color(0xFF448AFF);          // Blue accent

  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: primaryDark,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          secondary: warning,
          surface: surface,
          onSurface: onSurface,
          error: danger,
        ),
        textTheme: const TextTheme(
          // Tất cả text >= 24sp cho accessibility
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: onSurface,
          ),
          headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: onSurface,
          ),
          bodyLarge: TextStyle(
            fontSize: 24,
            color: onSurface,
          ),
          bodyMedium: TextStyle(
            fontSize: 24,
            color: onSurface,
          ),
          labelLarge: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 72),
            textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
}
