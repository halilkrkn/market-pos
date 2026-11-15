import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/features/diagnostics/presentation/widgets/outbox_status_badge.dart';
import 'package:mms_contracts/mms_contracts.dart';

/// W3C WCAG 2.1 Göreli Parlaklık (Relative Luminance) Hesabı
double calculateRelativeLuminance(Color color) {
  double channelToLinear(double val) {
    return (val <= 0.04045)
        ? (val / 12.92)
        : pow((val + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channelToLinear(color.r);
  final g = channelToLinear(color.g);
  final b = channelToLinear(color.b);

  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// W3C WCAG 2.1 Kontrast Oranı Hesabı: (L1 + 0.05) / (L2 + 0.05)
double calculateWcagContrast(Color c1, Color c2) {
  final l1 = calculateRelativeLuminance(c1);
  final l2 = calculateRelativeLuminance(c2);
  final lighter = max(l1, l2);
  final darker = min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('OutboxStatusBadge - Senkronizasyon Kuyruk Rozeti Testleri', () {
    testWidgets('1. Boş Kuyruk: SENKRONİZE rozeti ve yeşil stil render edilir',
        (WidgetTester tester) async {
      const summary = OutboxSummary(
        pending: 0,
        retry: 0,
        inProgress: 0,
        failedPermanent: 0,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OutboxStatusBadge(summary: summary),
          ),
        ),
      );

      expect(find.text('SENKRONİZE'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
    });

    testWidgets('2. Bekleyen İşlemler: X BEKLİYOR rozeti ve uyarı ikonu render edilir',
        (WidgetTester tester) async {
      const summary = OutboxSummary(
        pending: 3,
        retry: 2,
        inProgress: 1,
        failedPermanent: 0,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OutboxStatusBadge(summary: summary),
          ),
        ),
      );

      expect(find.text('6 BEKLİYOR'), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsOneWidget);
    });

    testWidgets('3. Kalıcı Hata: X HATA rozeti ve hata ikonu render edilir',
        (WidgetTester tester) async {
      const summary = OutboxSummary(
        pending: 1,
        retry: 0,
        inProgress: 0,
        failedPermanent: 2,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OutboxStatusBadge(summary: summary),
          ),
        ),
      );

      expect(find.text('2 HATA'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('4. Veritabanı Hatasında: Boş kuyruk SENKRONİZE gibi gösterilmez, KUYRUK OKUNAMIYOR render edilir',
        (WidgetTester tester) async {
      const summary = OutboxSummary.empty();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OutboxStatusBadge(
              summary: summary,
              isDatabaseError: true,
            ),
          ),
        ),
      );

      expect(find.text('SENKRONİZE'), findsNothing);
      expect(find.text('KUYRUK OKUNAMIYOR'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);

      final tooltipFinder = find.byType(Tooltip);
      expect(tooltipFinder, findsOneWidget);
      final tooltip = tester.widget<Tooltip>(tooltipFinder);
      expect(tooltip.message, contains('Yerel veritabanı okunamadığı için'));
    });

    testWidgets('5. Dark Tema Uyumluluğu: Koyu modda yüksek kontrastlı renkler render edilir',
        (WidgetTester tester) async {
      const summary = OutboxSummary(
        pending: 1,
        retry: 0,
        inProgress: 0,
        failedPermanent: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: OutboxStatusBadge(summary: summary),
          ),
        ),
      );

      expect(find.text('1 BEKLİYOR'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('1 BEKLİYOR'));
      expect(textWidget.style?.color, AppTheme.badgeWarningDarkText);
    });

    testWidgets('6. Tooltip: Kuyruk detaylarını içerir',
        (WidgetTester tester) async {
      const summary = OutboxSummary(
        pending: 2,
        retry: 1,
        inProgress: 0,
        failedPermanent: 1,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OutboxStatusBadge(summary: summary),
          ),
        ),
      );

      final tooltipFinder = find.byType(Tooltip);
      expect(tooltipFinder, findsOneWidget);

      final tooltip = tester.widget<Tooltip>(tooltipFinder);
      expect(tooltip.message, contains('Bekleyen: 2'));
      expect(tooltip.message, contains('Tekrar: 1'));
      expect(tooltip.message, contains('Kalıcı Hata: 1'));
    });

    group('7. W3C WCAG 2.1 Matematiksel Kontrast Doğrulaması (AppTheme)', () {
      test('7.1 Light Success (SENKRONİZE): AAA >= 7.0:1', () {
        final contrast = calculateWcagContrast(
          AppTheme.badgeSuccessText,
          AppTheme.badgeSuccessBg,
        );
        expect(contrast, greaterThanOrEqualTo(7.0),
            reason: 'Light Success AAA >= 7.0:1 olmalıdır (Aktüel: ${contrast.toStringAsFixed(2)}:1)');
      });

      test('7.2 Light Error (HATA / KUYRUK OKUNAMIYOR): AAA >= 7.0:1', () {
        final contrast = calculateWcagContrast(
          AppTheme.badgeErrorText,
          AppTheme.badgeErrorBg,
        );
        expect(contrast, greaterThanOrEqualTo(7.0),
            reason: 'Light Error AAA >= 7.0:1 olmalıdır (Aktüel: ${contrast.toStringAsFixed(2)}:1)');
      });

      test('7.3 Light Warning (BEKLİYOR): AAA >= 7.0:1', () {
        final contrast = calculateWcagContrast(
          AppTheme.badgeWarningText,
          AppTheme.badgeWarningBg,
        );
        expect(contrast, greaterThanOrEqualTo(7.0),
            reason: 'Light Warning AAA >= 7.0:1 olmalıdır (Aktüel: ${contrast.toStringAsFixed(2)}:1)');
      });

      test('7.4 Light Neutral (KONTROL): AAA >= 7.0:1', () {
        final contrast = calculateWcagContrast(
          AppTheme.badgeNeutralText,
          AppTheme.badgeNeutralBg,
        );
        expect(contrast, greaterThanOrEqualTo(7.0),
            reason: 'Light Neutral AAA >= 7.0:1 olmalıdır (Aktüel: ${contrast.toStringAsFixed(2)}:1)');
      });

      test('7.5 Dark Success (SENKRONİZE): AAA >= 7.0:1', () {
        final contrast = calculateWcagContrast(
          AppTheme.badgeSuccessDarkText,
          AppTheme.badgeSuccessDarkBg,
        );
        expect(contrast, greaterThanOrEqualTo(7.0),
            reason: 'Dark Success AAA >= 7.0:1 olmalıdır (Aktüel: ${contrast.toStringAsFixed(2)}:1)');
      });

      test('7.6 Dark Error (HATA / KUYRUK OKUNAMIYOR): AAA >= 7.0:1', () {
        final contrast = calculateWcagContrast(
          AppTheme.badgeErrorDarkText,
          AppTheme.badgeErrorDarkBg,
        );
        expect(contrast, greaterThanOrEqualTo(7.0),
            reason: 'Dark Error AAA >= 7.0:1 olmalıdır (Aktüel: ${contrast.toStringAsFixed(2)}:1)');
      });

      test('7.7 Dark Warning (BEKLİYOR): AAA >= 7.0:1', () {
        final contrast = calculateWcagContrast(
          AppTheme.badgeWarningDarkText,
          AppTheme.badgeWarningDarkBg,
        );
        expect(contrast, greaterThanOrEqualTo(7.0),
            reason: 'Dark Warning AAA >= 7.0:1 olmalıdır (Aktüel: ${contrast.toStringAsFixed(2)}:1)');
      });

      test('7.8 Dark Neutral (KONTROL): AAA >= 7.0:1', () {
        final contrast = calculateWcagContrast(
          AppTheme.badgeNeutralDarkText,
          AppTheme.badgeNeutralDarkBg,
        );
        expect(contrast, greaterThanOrEqualTo(7.0),
            reason: 'Dark Neutral AAA >= 7.0:1 olmalıdır (Aktüel: ${contrast.toStringAsFixed(2)}:1)');
      });
    });

    testWidgets('8. Widget Seviyesinde İkon, Metin ve Arka Plan Tema Uyumu ve Kontrastı',
        (WidgetTester tester) async {
      // Light Mod Doğrulaması
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OutboxStatusBadge(
              summary: OutboxSummary(pending: 2, retry: 0, inProgress: 0, failedPermanent: 0),
            ),
          ),
        ),
      );

      final lightIcon = tester.widget<Icon>(find.byIcon(Icons.sync));
      final lightText = tester.widget<Text>(find.text('2 BEKLİYOR'));
      final lightContainer = tester.widget<Container>(find.byType(Container));
      final lightBoxDeco = lightContainer.decoration as BoxDecoration;

      // İkon ve metin rengi tam eşleşmeli
      expect(lightIcon.color, equals(lightText.style?.color));
      // Arka plan rengi ile metin rengi arasındaki kontrast AAA (>=7.0:1) olmalı
      final lightContrast = calculateWcagContrast(lightText.style!.color!, lightBoxDeco.color!);
      expect(lightContrast, greaterThanOrEqualTo(7.0));

      // Dark Mod Doğrulaması
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: OutboxStatusBadge(
              summary: OutboxSummary(pending: 0, retry: 0, inProgress: 0, failedPermanent: 1),
            ),
          ),
        ),
      );

      final darkIcon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      final darkText = tester.widget<Text>(find.text('1 HATA'));
      final darkContainer = tester.widget<Container>(find.byType(Container));
      final darkBoxDeco = darkContainer.decoration as BoxDecoration;

      // İkon ve metin rengi dark modda da tam eşleşmeli
      expect(darkIcon.color, equals(darkText.style?.color));
      // Arka plan rengi ile metin rengi arasındaki kontrast AAA (>=7.0:1) olmalı
      final darkContrast = calculateWcagContrast(darkText.style!.color!, darkBoxDeco.color!);
      expect(darkContrast, greaterThanOrEqualTo(7.0));
    });
  });
}
