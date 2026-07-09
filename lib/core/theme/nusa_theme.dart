import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';

class NusaTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: NusaConfig.backgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: NusaConfig.primaryColor,
          primary: NusaConfig.primaryColor,
          surface: NusaConfig.surfaceColor,
        ),
        textTheme: GoogleFonts.interTextTheme().copyWith(
          displaySmall: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: NusaConfig.textPrimary),
          titleLarge: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: NusaConfig.textPrimary),
          titleMedium: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2),
          bodyMedium: GoogleFonts.inter(fontSize: 15),
          labelMedium: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: NusaConfig.textSecondary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: NusaConfig.primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        cardTheme: CardThemeData(
          color: NusaConfig.surfaceColor,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      );
}
