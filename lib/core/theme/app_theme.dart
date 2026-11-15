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

  // Rozet Semantik Renkleri (Light Tema - WCAG AAA > 7:1 Kontrast)
  static const Color badgeSuccessBg = Color(0xFFDCFCE7); // Green 100
  static const Color badgeSuccessText = Color(0xFF14532D); // Emerald 900 (8.30:1 - WCAG AAA)
  static const Color badgeErrorBg = Color(0xFFFEE2E2); // Red 100
  static const Color badgeErrorText = Color(0xFF7F1D1D); // Red 900 (8.20:1 - WCAG AAA)
  static const Color badgeWarningBg = Color(0xFFFEF3C7); // Amber 100
  static const Color badgeWarningText = Color(0xFF78350F); // Amber 900 (8.15:1 - WCAG AAA)
  static const Color badgeNeutralBg = Color(0xFFE2E8F0); // Slate 200
  static const Color badgeNeutralText = Color(0xFF1E293B); // Slate 800 (11.87:1 - WCAG AAA)

  // Rozet Semantik Renkleri (Dark Tema - WCAG AAA >= 7.0:1 Kontrast)
  static const Color badgeSuccessDarkBg = Color(0xFF052E16); // Green 950 (10.62:1 - WCAG AAA)
  static const Color badgeSuccessDarkText = Color(0xFF86EFAC); // Green 300
  static const Color badgeErrorDarkBg = Color(0xFF450A0A); // Red 950 (8.51:1 - WCAG AAA)
  static const Color badgeErrorDarkText = Color(0xFFFCA5A5); // Red 300
  static const Color badgeWarningDarkBg = Color(0xFF451A03); // Amber 950 (10.39:1 - WCAG AAA)
  static const Color badgeWarningDarkText = Color(0xFFFCD34D); // Amber 300
  static const Color badgeNeutralDarkBg = Color(0xFF0F172A); // Slate 900 (12.02:1 - WCAG AAA)
  static const Color badgeNeutralDarkText = Color(0xFFCBD5E1); // Slate 300

  // POS Aksiyon & Semantik Yüksek Kontrast Renkleri (UX Handoff Uyumlu)
  static const Color posCashAction = Color(0xFF047857);
  static const Color posCashBg = Color(0xFFECFDF5);
  static const Color posCashText = Color(0xFF166534);
  static const Color posWarningBg = Color(0xFFFFFBEB);
  static const Color posWarningText = Color(0xFF92400E);
  static const Color posDangerBg = Color(0xFFFEF2F2);
  static const Color posDangerText = Color(0xFF991B1B);
  static const Color posInfoBg = Color(0xFFEFF6FF);

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
