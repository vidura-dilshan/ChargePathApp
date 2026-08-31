import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0253A4);
  static const Color primaryDark = Color(0xFF034485);

  static const Color background = Color(0xFFF5F7FA);
  static const Color lightFill = Color(0xFFE6EFF8);

  static const Color success = Color(0xFF00C853);
  static const Color warning = Color(0xFFFF9800);
  static const Color danger = Color(0xFFE57373);

  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);

  static const Color white = Colors.white;

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [
      primary,
      primaryDark,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}