import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/platform/mms_ui_profile.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/barcode_scanner/barcode_scanner_providers.dart';
import 'package:market_pos/features/barcode_scanner/domain/camera_scan_result.dart';
import 'package:market_pos/features/barcode_scanner/domain/continuous_scan_session.dart';
import 'package:market_pos/features/barcode_scanner/presentation/camera_barcode_scanner_service.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/stock/presentation/screens/stock_receipt_screen.dart';

class _FakeScanner implements CameraBarcodeScannerService {
  final String barcode;
  _FakeScanner(this.barcode);

  @override
  Future<CameraScanResult> scanBarcode(
    BuildContext context, {
    String title = '',
    String subtitle = '',
  }) async =>
      CameraScanResult.scanned(barcode);

  @override
  Future<CameraScanResult> scanQrCode(
    BuildContext context, {
    String title = '',
    String subtitle = '',
  }) async =>
      CameraScanResult.scanned(barcode);

  @override
  Future<CameraScanResult> scanContinuously(
    BuildContext context, {
    required Future<ScanFeedback> Function(String barcode) onBarcode,
    String title = '',
    String subtitle = '',
  }) async =>
      const CameraScanResult.cancelled();
}

/// Faz 2 §4.3 — Stok Girişi ekranı widget testleri (Android kamera + Windows HID).
void main() {
  late LocalDatabaseService localDb;
  late MmsApiClient apiClient;

  setUp(() async {
    localDb = LocalDatabaseService.forTesting(
      NativeDatabase.memory(),
      path: 'C:\\Users\\Mock\\AppData\\Local\\MarketMMS\\stock_receipt_ui.db',
    );
    await localDb.repository.initializeDevice('POS-STOCK-UI');
    await localDb.repository.createProduct(
      name: 'Su 0.5L',
      price: 1000,
      barcode: '8690000000011',
      initialStock: 5000,
    );
    apiClient = MmsApiClient(
      client: MockClient((_) async => http.Response(jsonEncode({'status': 'HEALTHY'}), 200)),
      baseUrl: 'http://192.168.1.50:8945',
      deviceId: 'POS-STOCK-UI',
    );
  });

  tearDown(() async => localDb.close());

  Future<void> pumpScreen(WidgetTester tester, {required MmsUiProfile profile, required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          apiClientProvider.overrideWithValue(apiClient),
          mmsUiProfileProvider.overrideWithValue(profile),
          cameraBarcodeScannerProvider.overrideWithValue(_FakeScanner('8690000000011')),
        ],
        child: const MaterialApp(home: StockReceiptScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<int> receiptCount() async {
    final db = localDb.database;
    return (await (db.select(db.localStockMovements)
              ..where((m) => m.movementType.equals('GIRIS')))
            .get())
        .length;
  }

  testWidgets('Android (390x844): kamera ile ürün bulunur, 2 adet eklenir, stok 5→7 ve geçmişte görünür',
      (tester) async {
    await pumpScreen(tester, profile: const MmsUiProfile.mobile(), size: const Size(390, 844));

    final cameraBtn = find.byKey(const Key('stock_receipt_camera_button'));
    expect(cameraBtn, findsOneWidget);
    expect(tester.getSize(cameraBtn).height, greaterThanOrEqualTo(48));
    await tester.tap(cameraBtn);
    await tester.pumpAndSettle();

    expect(find.text('Su 0.5L'), findsOneWidget);
    expect(find.textContaining('Mevcut stok: 5'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('stock_receipt_quantity_field')), '2');
    await tester.enterText(find.byKey(const Key('stock_receipt_purchase_field')), '7,50');
    await tester.ensureVisible(find.byKey(const Key('stock_receipt_submit_button')));
    await tester.tap(find.byKey(const Key('stock_receipt_submit_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mevcut stok: 7'), findsOneWidget);
    expect(find.text('Stok girişi kaydedildi.'), findsOneWidget);
    expect(find.textContaining('STOK GİRİŞİ'), findsOneWidget);
    expect(find.textContaining('Alış: 7.50 TL'), findsOneWidget);
    expect(await receiptCount(), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows (1280x720): HID okuyucu barkodu yazıp Enter gönderir; bilinmeyen barkodda Yeni Ürün Ekle sunulur',
      (tester) async {
    await pumpScreen(tester, profile: const MmsUiProfile.desktop(), size: const Size(1280, 720));
    expect(find.byKey(const Key('stock_receipt_camera_button')), findsNothing);

    final barcodeField = find.byKey(const Key('stock_receipt_barcode_field'));
    await tester.enterText(barcodeField, '8699999999994');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.textContaining('bulunamadı'), findsOneWidget);
    expect(find.byKey(const Key('stock_receipt_new_product_button')), findsOneWidget);
    expect(find.byKey(const Key('stock_receipt_quantity_field')), findsNothing);

    await tester.enterText(barcodeField, '8690000000011');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Su 0.5L'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('stock_receipt_quantity_field')), '1,5');
    await tester.tap(find.byKey(const Key('stock_receipt_submit_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('kesirli'), findsOneWidget);
    expect(await receiptCount(), 0);
  });
}
