// İkincil barkod yönetimi — gerçek CatalogScreen → ProductBarcodesDialog → CatalogNotifier →
// ClientStorageRepository (bellek içi SQLite) → PRODUCT_UPSERT Outbox zinciri.
// Hub'a bağlantı yoktur (offline-first); Outbox durumları test içinde sentetik olarak
// değiştirilerek ürün bazlı senkron geri bildirimi doğrulanır.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/catalog/presentation/screens/catalog_screen.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

const _device = 'POS-WIN-BC-UI';

void main() {
  late LocalDatabaseService localDb;
  late LocalProduct simit;
  late LocalProduct pogaca;

  setUp(() async {
    localDb = LocalDatabaseService.forTesting(
      NativeDatabase.memory(),
      path: 'C:\\Users\\Mock\\AppData\\Local\\MarketMMS\\client_local.db',
    );
    final repo = localDb.repository;
    await repo.initializeDevice(_device);
    simit = await repo.createProduct(name: 'Simit', price: 1500, barcode: '8690077', deviceId: _device);
    pogaca = await repo.createProduct(name: 'Poğaça', price: 2000, barcode: '8690088', deviceId: _device);
    await repo.addProductBarcode(productId: simit.id, barcode: '2000000000015', deviceId: _device);
    await _setAllOutbox(localDb, 'SYNCED'); // başlangıç: Hub ile eşitlenmiş katalog
  });

  tearDown(() async {
    await localDb.close();
  });

  Widget app() => ProviderScope(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          apiClientProvider.overrideWithValue(
            MmsApiClient(
              client: MockClient((_) async => http.Response('{}', 200)),
              baseUrl: 'https://127.0.0.1:8443',
              deviceId: _device,
            ),
          ),
        ],
        child: const MaterialApp(home: CatalogScreen()),
      );

  Future<void> openBarcodeManager(WidgetTester tester, String productId) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('product_barcodes_button_$productId')));
    await tester.pumpAndSettle();
    expect(find.text('Barkod Yönetimi'), findsOneWidget);
  }

  Future<void> addViaDialog(WidgetTester tester, String barcode) async {
    await tester.enterText(find.byKey(const Key('secondary_barcode_input')), barcode);
    await tester.ensureVisible(find.byKey(const Key('secondary_barcode_add_button')));
    await tester.tap(find.byKey(const Key('secondary_barcode_add_button')));
    await tester.pumpAndSettle();
  }

  String feedback(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(
        of: find.byKey(const Key('product_barcode_feedback')),
        matching: find.byType(Text),
      ))
      .map((t) => t.data ?? '')
      .join(' ');

  testWidgets('Ürün detayında birincil ve ikincil barkodlar görüntülenir; Hub ile eşit durumu gösterilir', (tester) async {
    await openBarcodeManager(tester, simit.id);
    expect(find.byKey(const Key('product_primary_barcode')), findsOneWidget);
    expect(find.text('8690077'), findsOneWidget);
    expect(find.byKey(const Key('secondary_barcode_row_2000000000015')), findsOneWidget);
    expect(find.byKey(const Key('product_barcode_sync_status_synced')), findsOneWidget);
  });

  testWidgets('İkincil barkod eklenir (offline): yerel SQLite + Outbox, ürün bazlı "bekliyor" göstergesi', (tester) async {
    await openBarcodeManager(tester, simit.id);
    await addViaDialog(tester, '2000000000022');

    expect(find.byKey(const Key('secondary_barcode_row_2000000000022')), findsOneWidget);
    expect(feedback(tester), contains('eklendi'));
    expect(find.byKey(const Key('product_barcode_sync_status_pending')), findsOneWidget);

    final found = await localDb.repository.getProductByBarcode('2000000000022');
    expect(found?.id, simit.id, reason: 'Satış ekranı barkodu yerel katalogda hemen bulmalı.');
    final status = await localDb.repository.getProductCatalogSyncStatus(simit.id);
    expect(status.state, ProductCatalogSyncState.pending);

    // Liste satırında ürün bazlı rozet (genel Outbox rozetinden bağımsız)
    await tester.tap(find.byKey(const Key('product_barcodes_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('product_sync_badge_${simit.id}')), findsOneWidget);
    expect(find.byKey(Key('product_sync_badge_${pogaca.id}')), findsNothing);
  });

  testWidgets('Silme onayında Vazgeç: barkod korunur, Outbox kaydı oluşmaz', (tester) async {
    await openBarcodeManager(tester, simit.id);
    await tester.tap(find.byKey(const Key('remove_barcode_2000000000015')));
    await tester.pumpAndSettle();
    expect(find.text('İkincil Barkodu Sil'), findsOneWidget);
    await tester.tap(find.byKey(const Key('barcode_remove_cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('secondary_barcode_row_2000000000015')), findsOneWidget);
    expect((await localDb.repository.getProductCatalogSyncStatus(simit.id)).state,
        ProductCatalogSyncState.synced);
  });

  testWidgets('İkincil barkod onayla silinir; liste güncellenir ve barkod artık ürünü bulmaz', (tester) async {
    await openBarcodeManager(tester, simit.id);
    await tester.tap(find.byKey(const Key('remove_barcode_2000000000015')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('barcode_remove_confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('secondary_barcode_row_2000000000015')), findsNothing);
    expect(find.byKey(const Key('secondary_barcodes_empty')), findsOneWidget);
    expect(feedback(tester), contains('kaldırıldı'));
    expect(find.byKey(const Key('product_barcode_sync_status_pending')), findsOneWidget);
    expect(await localDb.repository.getProductByBarcode('2000000000015'), isNull);
  });

  testWidgets('Aynı ürüne aynı barkod tekrar eklenemez', (tester) async {
    await openBarcodeManager(tester, simit.id);
    await addViaDialog(tester, '2000000000015');
    expect(feedback(tester), contains('zaten ekli'));
    expect((await localDb.repository.getProductCatalogSyncStatus(simit.id)).state,
        ProductCatalogSyncState.synced, reason: 'Reddedilen işlem Outbox kaydı üretmemeli.');
  });

  testWidgets('Başka üründe kullanılan barkod eklenemez (ürün adı gösterilir)', (tester) async {
    await openBarcodeManager(tester, simit.id);
    await addViaDialog(tester, '8690088');
    expect(feedback(tester), contains('başka bir ürüne kayıtlı'));
    expect(feedback(tester), contains('Poğaça'));
    expect((await localDb.repository.getProductByBarcode('8690088'))?.id, pogaca.id);
  });

  testWidgets('Birincil barkod ikincil olarak eklenemez', (tester) async {
    await openBarcodeManager(tester, simit.id);
    await addViaDialog(tester, '8690077');
    expect(feedback(tester), contains('birincil barkodudur'));
  });

  testWidgets('Geçersiz biçimli barkod (boşluk/kontrol karakteri) reddedilir', (tester) async {
    await openBarcodeManager(tester, simit.id);
    await addViaDialog(tester, '12 34');
    expect(feedback(tester), contains('Geçersiz barkod'));
  });

  testWidgets('Outbox kalıcı hata: ürün bazlı hata bildirimi ve liste rozeti; senkron sonrası eşit durum', (tester) async {
    await localDb.repository.addProductBarcode(productId: simit.id, barcode: '2000000000039', deviceId: _device);
    await _setAllOutbox(localDb, 'FAILED_PERMANENT', lastError: 'HTTP 409 BARCODE_CONFLICT');

    await openBarcodeManager(tester, simit.id);
    expect(find.byKey(const Key('product_barcode_sync_status_failed')), findsOneWidget);
    expect(find.textContaining('GÖNDERİLEMEDİ'), findsOneWidget);
    expect(find.textContaining('BARCODE_CONFLICT'), findsOneWidget);
    await tester.tap(find.byKey(const Key('product_barcodes_close')));
    await tester.pumpAndSettle();
    expect(find.descendant(
      of: find.byKey(Key('product_sync_badge_${simit.id}')),
      matching: find.text('HUB HATASI'),
    ), findsOneWidget);

    // Sorun giderildi, Outbox Hub tarafından onaylandı → eşit durum, barkodlar doğru.
    await _setAllOutbox(localDb, 'SYNCED');
    await tester.tap(find.byKey(Key('product_barcodes_button_${simit.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('product_barcode_sync_status_synced')), findsOneWidget);
    expect(find.byKey(const Key('secondary_barcode_row_2000000000015')), findsOneWidget);
    expect(find.byKey(const Key('secondary_barcode_row_2000000000039')), findsOneWidget);
  });

  testWidgets('Dar (Android/touch-first) düzende ürün kartından barkod yönetimi açılır ve barkod eklenir', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('mobile_prod_${simit.id}')), findsOneWidget);
    await tester.tap(find.byKey(Key('product_barcodes_button_${simit.id}')));
    await tester.pumpAndSettle();
    await addViaDialog(tester, '2000000000046');
    expect(find.byKey(const Key('secondary_barcode_row_2000000000046')), findsOneWidget);
    final removeButton = tester.getSize(find.byKey(const Key('remove_barcode_2000000000046')));
    expect(removeButton.height, greaterThanOrEqualTo(44), reason: 'Dokunmatik hedef boyutu');
  });

  testWidgets('Masaüstü tablo düzeninde (1024 px) bekleyen senkron rozeti uzun ürün adıyla taşma üretmez', (tester) async {
    final longProduct = await localDb.repository.createProduct(
      name: 'Çok Uzun Adlı Organik Tam Buğday Ekşi Mayalı Köy Ekmeği 750 g',
      price: 4500,
      barcode: '8690000000999',
      deviceId: _device,
    ); // Outbox PENDING → rozet görünür
    tester.view.physicalSize = const Size(1024, 768); // >= 740 iç genişlik → masaüstü tablosu
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('Çok Uzun Adlı'), findsOneWidget);
    expect(find.byKey(Key('product_sync_badge_${longProduct.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ürün düzenleme (detay) ekranından ikincil barkod yönetimi açılır', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ürünü Düzenle').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('product_manage_secondary_barcodes_button')));
    await tester.tap(find.byKey(const Key('product_manage_secondary_barcodes_button')));
    await tester.pumpAndSettle();
    expect(find.text('Barkod Yönetimi'), findsOneWidget);
  });
}

Future<void> _setAllOutbox(LocalDatabaseService db, String status, {String? lastError}) async {
  await db.database.update(db.database.outboxOperations).write(OutboxOperationsCompanion(
        status: Value(status),
        lastError: Value(lastError),
      ));
}
