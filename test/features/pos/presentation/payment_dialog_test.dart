import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/features/pos/domain/pos_repository.dart';
import 'package:market_pos/features/pos/presentation/widgets/payment_dialog.dart';

void main() {
  group('PaymentDialog Mobil & Masaüstü Ergonomi Testleri', () {
    testWidgets('Mobil profilde (showKeyboardHints: false) F9/F10 devre dışı, autofocus kapalı ve preset butonlar >= 48dp',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => PaymentDialog(
                totalCents: 12500,
                initialMethod: PaymentMethod.cash,
                showKeyboardHints: false,
                onConfirmSale: ({
                  required paymentMethod,
                  cashReceivedCents,
                  required externalPosConfirmed,
                }) async =>
                    (sale: null, errorMessage: null),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nakit input autofocus mobil profilde false olmalı
      final cashField = tester.widget<TextField>(
        find.byKey(const Key('cash_received_input')),
      );
      expect(cashField.autofocus, isFalse);

      // Hızlı banknot butonları >= 48dp olmalı
      for (final label in ['Tam Tutar', '50 TL', '100 TL', '200 TL', '500 TL', 'Temizle']) {
        final btn = find.widgetWithText(OutlinedButton, label);
        expect(btn, findsOneWidget);
        expect(
          tester.getSize(btn).height,
          greaterThanOrEqualTo(48.0),
          reason: '$label butonu >= 48dp olmalı',
        );
      }

      // F9 tuşu mobilde Kart sekmesine geçirmemeli
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cash_received_input')), findsOneWidget);
      expect(find.byKey(const Key('card_manual_confirm_checkbox')), findsNothing);
    });

    testWidgets('Masaüstü profilde (showKeyboardHints: true) autofocus aktif ve F9/F10 çalışır',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: PaymentDialog(
              totalCents: 12500,
              initialMethod: PaymentMethod.cash,
              showKeyboardHints: true,
              onConfirmSale: ({
                required paymentMethod,
                cashReceivedCents,
                required externalPosConfirmed,
              }) async =>
                  (sale: null, errorMessage: null),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cashField = tester.widget<TextField>(
        find.byKey(const Key('cash_received_input')),
      );
      expect(cashField.autofocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card_manual_confirm_checkbox')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cash_received_input')), findsOneWidget);
    });
  });
}
