// lib/theme/app_theme.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Primary
  static const primary = Color(0xFF2F80ED);
  static const primaryDark = Color(0xFF2563EB);
  static const primaryLight = Color(0xFF56CCF2);

  // Backgrounds
  static const background = Color(0xFFF7FAFC);
  static const surface = Colors.white;

  // Text
  static const text = Color(0xFF1F2937);
  static const textSecondary = Color(0xFF6B7280);

  // Status
  static const success = Color(0xFF27AE60);
  static const warning = Color(0xFFF2C94C);
  static const danger = Color(0xFFEB5757);

  // Border
  static const border = Color(0xFFE5E7EB);

  static const white = Colors.white;

  // Compatibility with existing code
  static const navy = primary;
  static const navy2 = primaryDark;
  static const navy3 = primaryLight;
  static const ivory = background;
  static const ivory2 = background;
  static const cream = surface;
  static const gold = warning;
  static const gold2 = warning;
  static const green = success;
  static const amber = warning;
  static const red = danger;
  static const text2 = textSecondary;
  static const text3 = textSecondary;
}

class AppTextStyles {
  static TextStyle mono(double size, FontWeight weight, Color color) =>
      GoogleFonts.jetBrainsMono(
          fontSize: size, fontWeight: weight, color: color);

  static TextStyle outfit(double size, FontWeight weight, Color color) =>
      GoogleFonts.outfit(fontSize: size, fontWeight: weight, color: color);

  static TextStyle playfair(double size, FontWeight weight, Color color) =>
      GoogleFonts.playfairDisplay(
          fontSize: size, fontWeight: weight, color: color);
}

ThemeData buildAppTheme() {
  return ThemeData(
    scaffoldBackgroundColor: AppColors.navy,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.gold,
      surface: AppColors.navy,
    ),
    textTheme: GoogleFonts.outfitTextTheme(),
    useMaterial3: true,
  );
}
