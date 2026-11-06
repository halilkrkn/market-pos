import 'package:flutter/material.dart';

/// MARKET MMS - Kasa Ergonomisi ve Yüksek Kontrast Teması (UI Standards)
///
/// WCAG AAA kontrast kuralları, Fitts kanunu (>=48dp touch targets)
/// ve sayısal hizalama (Tabular Figures) standartlarına uygun olarak tasarlanmıştır.
class AppTheme {
  // Renk Paleti - Yüksek Kontrastlı Kurumsal Perakende
  static const Color primaryBlue = Color(0xFF1E40AF); // Mavi 800
  static const Color primaryDark = Color(0xFF0F172A); // Slate 900
  static const Color surfaceLight = Color(0xFFF8FAFC); // Slate 50
  static const Color cardBgLight = Colors.white;
  static const Color textMainLight = Color(0xFF0F172A); // WCAG AAA Kontrast (> 10:1)
  static const Color textMutedLight = Color(0xFF475569); // Slate 600 (> 4.5:1)
  static const Color borderSubtle = Color(0xFFCBD5E1); // Slate 300

  // Durum Renkleri
  static const Color statusOnline = Color(0xFF15803D); // Emerald 700 (Canlı / Çevrimiçi)
  static const Color statusOffline = Color(0xFFB91C1C); // Red 700 (Çevrimdışı / Hata)
  static const Color statusWarning = Color(0xFFB45309); // Amber 700 (Draining / Beklemede)

  // Sayısal / Monospace Font Özelliği (Tabular Figures)
  static const List<FontFeature> tabularFiguresFeature = [
    FontFeature.tabularFigures(),
  ];

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: const Color(0xFF0284C7),
        surface: surfaceLight,
        error: statusOffline,
      ),
      scaffoldBackgroundColor: surfaceLight,
      cardTheme: CardThemeData(
        color: cardBgLight,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: borderSubtle, width: 1),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textMainLight,
          fontFeatures: tabularFiguresFeature,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textMainLight,
          fontFeatures: tabularFiguresFeature,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textMainLight,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textMainLight,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          color: textMainLight,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: textMutedLight,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      // Fitts Kanunu: Minimum 48dp Buton Hedef Boyutları
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: borderSubtle, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconTheme: const IconThemeData(
        size: 24,
        color: primaryBlue,
      ),
    );
  }
}
