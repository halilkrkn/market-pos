import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/logging/redacting_logger.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/security/security_providers.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/core/utils/user_friendly_error_mapper.dart';
import 'package:market_pos/features/catalog/catalog_providers.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/diagnostics/domain/system_status.dart';
import 'package:market_pos/features/pos/application/cart_notifier.dart';
import 'package:market_pos/features/pos/domain/cart_state.dart';
import 'package:market_pos/features/pos/domain/pos_product.dart';
import 'package:market_pos/features/pos/domain/pos_repository.dart';
import 'package:market_pos/features/security/data/hub_pairing_admin_client.dart';
import 'package:market_pos/features/security/presentation/widgets/pairing_approval_panel.dart';
import 'package:market_pos/features/stock/application/stock_receipt_notifier.dart';
import 'package:market_pos/features/sync/application/background_sync_coordinator.dart';
import 'package:market_pos/features/sync/application/hub_connection_notifier.dart';
import 'package:market_pos/features/sync/domain/hub_discovery_client.dart';
import 'package:market_pos/features/sync/domain/sync_coordinator_state.dart';
import 'package:market_pos/features/sync/sync_providers.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void main() {
  group('AUD-LOW-01: Güvenli Loglama, Maskeleme & Sessiz Catch Engeli (Client)', () {
    test(
      '1. RedactingLogger ve UserFriendlyErrorMapper tüm token, parola, sır, PEM anahtar ve tam yerel dosya yollarını maskeler; URL yapılarını korur',
      () {
        final logger = RedactingLogger();
        logger.registerSensitiveValue('SuperDpapiSecret-2026!');

        const rawSample =
            'Authorization: Bearer my_secret_jwt_123 '
            'device=mms_dt_live_987654 '
            'oauth=ya29.a0AfH6SMFakeAccessToken99 '
            'refresh=1//0gFakeRefreshToken88 '
            'client=GOCSPX-FakeClientSecret77 '
            'dpapi=SuperDpapiSecret-2026! '
            'JSON={"recovery_password":"Kurtarma-Parola-99","access_token":"ya29.tok2","refresh_token":"1//ref2","signing_key":"sig_priv_99","x-mms-admin-secret":"adm_sec_11"} '
            'winPath=C:\\Users\\halil\\AppData\\Local\\MarketMMS\\client_local.db '
            'hubPath=C:\\ProgramData\\MarketMMS\\data\\market_master.db '
            'androidPath=/data/data/com.marketmms.market_pos/app_flutter/client_local.db '
            'hubUrl=https://192.168.1.50:8945/api/v1/sales '
            '-----BEGIN EC PRIVATE KEY-----\nMHcCAQEEIPvt\n-----END EC PRIVATE KEY-----';

        final redacted = logger.redact(rawSample);

        expect(redacted, isNot(contains('my_secret_jwt_123')));
        expect(redacted, isNot(contains('mms_dt_live_987654')));
        expect(redacted, isNot(contains('ya29.a0AfH6SMFakeAccessToken99')));
        expect(redacted, isNot(contains('1//0gFakeRefreshToken88')));
        expect(redacted, isNot(contains('GOCSPX-FakeClientSecret77')));
        expect(redacted, isNot(contains('SuperDpapiSecret-2026!')));
        expect(redacted, isNot(contains('Kurtarma-Parola-99')));
        expect(redacted, isNot(contains('ya29.tok2')));
        expect(redacted, isNot(contains('1//ref2')));
        expect(redacted, isNot(contains('sig_priv_99')));
        expect(redacted, isNot(contains('adm_sec_11')));
        expect(redacted, isNot(contains('MHcCAQEEIPvt')));

        // Tam yerel dosya yolları maskelenirken dosya taban adı ve URL korunmalıdır
        expect(redacted, isNot(contains(r'C:\Users\halil')));
        expect(redacted, isNot(contains(r'C:\ProgramData\MarketMMS\data')));
        expect(redacted, isNot(contains('/data/data/com.marketmms.market_pos')));
        expect(redacted, contains('client_local.db'));
        expect(redacted, contains('market_master.db'));
        expect(redacted, contains('[REDACTED_PATH]'));
        expect(redacted, contains('https://192.168.1.50:8945/api/v1/sales'));

        // UserFriendlyErrorMapper son kullanıcıya tam dosya yolu veya token göstermemelidir
        final mapped = UserFriendlyErrorMapper.map(
          Exception(
            'Dosya açılamadı: C:\\ProgramData\\MarketMMS\\backups\\hub_bak.mmsbak token=mms_dt_secret_5',
          ),
        );
        expect(mapped, isNot(contains(r'C:\ProgramData')));
        expect(mapped, isNot(contains('mms_dt_secret_5')));
        expect(mapped, contains('hub_bak.mmsbak'));
      },
    );

    testWidgets(
      '2. PairingApprovalPanel /health okuma hatasını sessizce yutmaz, RedactingLogger ile uyarı yazar',
      (tester) async {
        final logger = RedactingLogger();
        final adminClient = HubPairingAdminClient(
          hubBaseUrl: 'https://127.0.0.1:8945',
          httpClient: MockClient((req) async {
            if (req.url.path.endsWith('/requests')) {
              return http.Response(jsonEncode({'requests': const []}), 200);
            }
            if (req.url.path.endsWith('/health')) {
              throw const FormatException('Boş/bozuk sağlık JSON yanıtı');
            }
            return http.Response('{}', 404);
          }),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              redactingLoggerProvider.overrideWithValue(logger),
              hubPairingAdminClientProvider.overrideWithValue(adminClient),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const Scaffold(
                body: SingleChildScrollView(child: PairingApprovalPanel()),
              ),
            ),
          ),
        );

        await tester.enterText(
          find.byKey(const Key('pairing_admin_secret_field')),
          'dogru_anahtar',
        );
        await tester.tap(find.byKey(const Key('pairing_refresh_button')));
        await tester.pumpAndSettle();

        expect(
          logger.entries.any(
            (e) =>
                e.level == RedactedLogLevel.warning &&
                e.category == 'pairing',
          ),
          isTrue,
          reason:
              'fetchHubReadiness hatası sessiz catch (_) {} içinde yutulmamalı, RedactingLogger kaydı düşmelidir.',
        );
      },
    );

    test(
      '3. URL sorgu gizlileri, ileri/boşluklu Windows yolları, POSIX kökleri ve stack frame yolları maskelenir',
      () {
        final logger = RedactingLogger();
        const rawInput =
            'oauthCb=http://127.0.0.1:54321/cb?code=4/0AX4XfWhSecretAuthCode&state=st_ok '
            'driveSess=https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=ADPycdvSecretSession99&key=AIzaSyFakeApiKey88 '
            'apiQuery=https://hub.local/api?access_token=tok_q1&refresh_token=ref_q2&page=1 '
            'fwdWin=C:/Users/halil/AppData/Local/MarketMMS/client_local.db '
            "quotedWin='C:\\Users\\Halil Ibrahim\\AppData\\Local\\MarketMMS\\client_local.db' "
            'dqWin="C:\\Program Files\\MarketMMS\\bin\\mms_backend.exe" '
            'unc=\\\\FILESERVER\\MarketShare\\backups\\hub.mmsbak '
            'sdcard=/sdcard/Download/restore_pkg.mmsbak '
            'macos="/Users/halil/Library/Application Support/MarketMMS/client.db" '
            'vol=/Volumes/USB_DISK/hub.mmsbak\n'
            '#0      main (file:///C:/Users/halil/Github/market-pos/lib/main.dart:40:5)';

        final fromLogger = logger.redact(rawInput);
        final fromMapper = UserFriendlyErrorMapper.redactSecrets(rawInput);

        for (final output in [fromLogger, fromMapper]) {
          // Hassas URL query parametreleri ve sırları sızmaz
          expect(output, isNot(contains('4/0AX4XfWhSecretAuthCode')));
          expect(output, isNot(contains('ADPycdvSecretSession99')));
          expect(output, isNot(contains('AIzaSyFakeApiKey88')));
          expect(output, isNot(contains('tok_q1')));
          expect(output, isNot(contains('ref_q2')));
          // Hassas olmayan URL yapıları ve query alanları korunur
          expect(output, contains('http://127.0.0.1:54321/cb'));
          expect(output, contains('&state=st_ok'));
          expect(output, contains('&page=1'));
          // Windows ileri eğik çizgi, boşluklu tırnaklı yollar, UNC, Android/macOS POSIX yolları maskelenir
          expect(output, isNot(contains('C:/Users/halil')));
          expect(output, isNot(contains(r'C:\Users\Halil Ibrahim')));
          expect(output, isNot(contains(r'C:\Program Files\MarketMMS')));
          expect(output, isNot(contains(r'\\FILESERVER\MarketShare')));
          expect(output, isNot(contains('/sdcard/Download')));
          expect(output, isNot(contains('/Users/halil/Library/Application Support')));
          expect(output, isNot(contains('/Volumes/USB_DISK')));
          expect(output, contains('client_local.db'));
          expect(output, contains('mms_backend.exe'));
          expect(output, contains('restore_pkg.mmsbak'));
          expect(output, contains('client.db'));
          expect(output, contains('main.dart:40:5'));
        }
      },
    );

    test(
      '4. CartNotifier, StockReceiptNotifier, catalogProvider ve HubConnectionNotifier loglarında tüm sırlar, OAuth/query parametreleri, dosya ve stack trace yolları maskelenir',
      () async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        const winDbPath =
            r'C:\Users\halil\AppData\Local\MarketMMS\client_local.db';
        const androidDbPath =
            '/data/data/com.marketmms.market_pos/files/mms_client.db';
        const stackUri =
            'file:///C:/Users/halil/Github/market-pos/lib/features/pos/data/local_pos_repository.dart:42:7';
        const secretPayload =
            'Bearer JwtSecret123 mms_dt_dev_secret_55 '
            'ya29.SecretAccess99 1//0gSecretRefresh88 GOCSPX-ClientSec77 '
            'recovery_password=RecPass-2026! x-mms-admin-secret: AdmSec-99 '
            '{"recovery_password":"JsonRecPass-77","admin_secret":"JsonAdm-88"} '
            'https://hub.local/cb?code=4/0AXAuthSecret&upload_id=ResumableSessSecret&api_key=AIzaKeySecret&state=keep_ok '
            '$winDbPath $androidDbPath';
        final fakeStack = StackTrace.fromString(
          '#0      _fail ($stackUri)\n'
          '#1      _call (file:///data/user/0/com.marketmms/app_flutter/sync_worker.dart:88:3)',
        );

        final capturedLogs = <String>[];
        final originalDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) capturedLogs.add(message);
        };
        addTearDown(() => debugPrint = originalDebugPrint);

        // 4a. CartNotifier: scanBarcode hatası, completeSale repo hatası ve onSaleCommitted hatası
        const sampleProduct = PosProduct(
          id: 'prod_1',
          primaryBarcode: '8690001000011',
          name: 'Deneme Süt',
          priceCents: 2500,
          priceVersionId: 'pv_1',
          stockMilli: 10000,
          stockUnit: 'adet',
          pricingUnit: 'adet',
          conversionFactorNumerator: 1,
          conversionFactorDenominator: 1,
          isActive: true,
        );
        final cartRepo = _SecretThrowingPosRepository(
          product: sampleProduct,
          secretPayload: secretPayload,
          fakeStack: fakeStack,
        );
        var failCommitCallback = false;
        final cartNotifier = CartNotifier(
          repository: cartRepo,
          readDeviceId: () => 'POS-TEST-01',
          onSaleCommitted: () async {
            if (failCommitCallback) {
              Error.throwWithStackTrace(
                Exception('PostCommit $secretPayload'),
                fakeStack,
              );
            }
          },
        );
        addTearDown(cartNotifier.dispose);

        final scanOk = await cartNotifier.scanBarcode('8690001000011');
        expect(scanOk, isFalse);
        expect(
          cartNotifier.state.errorMessage,
          'Barkod sorgulanırken beklenmeyen bir hata oluştu.',
        );

        cartRepo.failScan = false;
        expect(await cartNotifier.scanBarcode('8690001000011'), isTrue);

        cartRepo.failSale = true;
        final failedSale = await cartNotifier.completeSale(
          paymentMethod: PaymentMethod.cash,
          cashReceivedCents: 5000,
        );
        expect(failedSale, isNull);
        expect(cartNotifier.state.isProcessing, isFalse);

        cartRepo.failSale = false;
        failCommitCallback = true;
        final completedSale = await cartNotifier.completeSale(
          paymentMethod: PaymentMethod.cash,
          cashReceivedCents: 5000,
        );
        expect(completedSale, isNotNull);

        // 4b. StockReceiptNotifier: lookupBarcode ve submit hataları
        final stockDb = LocalDatabaseService.forTesting(NativeDatabase.memory());
        addTearDown(stockDb.close);
        final stockRepo = _SecretThrowingStockRepository(
          stockDb.database,
          secretPayload: secretPayload,
          fakeStack: fakeStack,
        );
        final stockNotifier = StockReceiptNotifier(
          repository: stockRepo,
          readDeviceId: () => 'POS-STOCK-01',
        );
        addTearDown(stockNotifier.dispose);

        await stockNotifier.lookupBarcode('8690001000011');
        expect(stockNotifier.state.phase, StockReceiptPhase.idle);
        expect(stockNotifier.state.isError, isTrue);

        stockRepo.failLookup = false;
        await stockNotifier.lookupBarcode('8690001000011');
        expect(stockNotifier.state.phase, StockReceiptPhase.productFound);

        stockRepo.failSubmit = true;
        final submitOk = await stockNotifier.submit(rawQuantity: '3');
        expect(submitOk, isFalse);
        expect(stockNotifier.state.phase, StockReceiptPhase.productFound);
        expect(stockNotifier.state.isError, isTrue);

        // 4c. catalogProvider: onProductChanged hem async hem sync hata yolları
        for (final syncThrow in [false, true]) {
          final catDb = LocalDatabaseService.forTesting(NativeDatabase.memory());
          final apiClient = MmsApiClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            baseUrl: 'https://127.0.0.1:8945',
            deviceId: 'POS-CAT-01',
          );
          final catContainer = ProviderContainer(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(catDb),
              apiClientProvider.overrideWithValue(apiClient),
              systemStatusProvider.overrideWith(
                (ref) => _FailingSystemStatusNotifier(
                  apiClient: apiClient,
                  localDbService: catDb,
                  syncThrow: syncThrow,
                  secretPayload: secretPayload,
                  fakeStack: fakeStack,
                ),
              ),
              backgroundSyncCoordinatorProvider.overrideWith(
                (ref) => _FailingSyncCoordinator(
                  repository: catDb.repository,
                  syncThrow: syncThrow,
                  secretPayload: secretPayload,
                  fakeStack: fakeStack,
                ),
              ),
            ],
          );

          final catNotifier = catContainer.read(catalogProvider.notifier);
          await catNotifier.init();
          final created = await catNotifier.createProduct(
            name: 'Deneme Ürün ${syncThrow ? "Sync" : "Async"}',
            price: 1500,
            barcode: '86900020000${syncThrow ? "2" : "1"}',
          );
          expect(created, isTrue);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          catContainer.dispose();
          await catDb.close();
        }

        // 4d. HubConnectionNotifier & hubConnectionProvider: UDP keşif ve başlangıç yükleme hatası
        final hubDb = LocalDatabaseService.forTesting(NativeDatabase.memory());
        final hubApi = MmsApiClient(
          client: MockClient((_) async => http.Response('{}', 200)),
          baseUrl: 'https://127.0.0.1:8945',
          deviceId: 'POS-HUB-01',
        );
        final hubContainer = ProviderContainer(
          overrides: [
            localDatabaseServiceProvider.overrideWithValue(
              _SecretFailingLocalDbService(
                hubDb,
                _SecretThrowingHubRepository(
                  hubDb.database,
                  secretPayload: secretPayload,
                  fakeStack: fakeStack,
                ),
              ),
            ),
            apiClientProvider.overrideWithValue(hubApi),
            hubAllowLoopbackPolicyProvider.overrideWithValue(true),
            hubDiscoveryClientProvider.overrideWithValue(
              _SecretFailingHubDiscoveryClient(secretPayload, fakeStack),
            ),
          ],
        );
        final hubNotifier = hubContainer.read(hubConnectionProvider.notifier);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final discovered = await hubNotifier.discoverAndConnect(
          timeout: const Duration(milliseconds: 50),
        );
        expect(discovered, isFalse);
        hubContainer.dispose();
        await hubDb.close();

        final joined = capturedLogs.join('\n');
        expect(joined, contains('[CartNotifier] Barkod sorgu hatası:'));
        expect(joined, contains('[CartNotifier] Satış kaydetme hatası:'));
        expect(
          joined,
          contains('[CartNotifier] Satış sonrası durum yenileme hatası'),
        );
        expect(joined, contains('[StockReceipt] Barkod sorgu hatası:'));
        expect(joined, contains('[StockReceipt] Kayıt hatası:'));
        expect(joined, contains('[catalog_providers] refreshLocalMetrics hatası:'));
        expect(
          joined,
          contains('[catalog_providers] refreshLocalMetrics erişim hatası:'),
        );
        expect(joined, contains('[catalog_providers] triggerSync hatası:'));
        expect(joined, contains('[catalog_providers] triggerSync erişim hatası:'));
        expect(joined, contains('[HubConnectionNotifier] UDP keşif hatası:'));
        expect(joined, contains('[HubConnectionNotifier] Başlangıç yükleme hatası:'));

        for (final forbidden in const [
          'JwtSecret123',
          'mms_dt_dev_secret_55',
          'ya29.SecretAccess99',
          '1//0gSecretRefresh88',
          'GOCSPX-ClientSec77',
          'RecPass-2026!',
          'AdmSec-99',
          'JsonRecPass-77',
          'JsonAdm-88',
          '4/0AXAuthSecret',
          'ResumableSessSecret',
          'AIzaKeySecret',
          r'C:\Users\halil',
          'C:/Users/halil',
          '/data/data/com.marketmms',
          '/data/user/0/com.marketmms',
        ]) {
          expect(
            joined,
            isNot(contains(forbidden)),
            reason: 'Log çıktısı hassas değer sızdırmamalı: $forbidden',
          );
        }
        expect(joined, contains('client_local.db'));
        expect(joined, contains('mms_client.db'));
        expect(joined, contains('local_pos_repository.dart:42:7'));
        expect(joined, contains('&state=keep_ok'));
      },
    );
  });
}

class _SecretThrowingPosRepository implements PosRepository {
  final PosProduct product;
  final String secretPayload;
  final StackTrace fakeStack;
  bool failScan = true;
  bool failSale = false;

  _SecretThrowingPosRepository({
    required this.product,
    required this.secretPayload,
    required this.fakeStack,
  });

  @override
  Future<BarcodeLookupResult> findByBarcode(String barcode) async {
    if (failScan) {
      Error.throwWithStackTrace(
        FileSystemException('Barkod DB hatası: $secretPayload', r'C:\Users\halil\AppData\Local\MarketMMS\client_local.db'),
        fakeStack,
      );
    }
    return BarcodeLookupResult.found(product, barcode);
  }

  @override
  Future<List<PosProduct>> searchActiveProducts(
    String query, {
    int limit = 50,
  }) async =>
      [product];

  @override
  Future<PosCompletedSale> completeOfflineSale({
    required String deviceId,
    required CartState cart,
    required PaymentMethod paymentMethod,
    int? cashReceivedCents,
    required bool externalPosConfirmed,
  }) async {
    if (failSale) {
      Error.throwWithStackTrace(
        Exception('Satış DB hatası: $secretPayload'),
        fakeStack,
      );
    }
    return PosCompletedSale(
      saleId: 'csale_ok_1',
      deviceId: deviceId,
      clientSeq: 1,
      totalAmountCents: cart.totalCents,
      paymentMethod: paymentMethod,
      cashReceivedCents: cashReceivedCents,
      cashChangeCents: cashReceivedCents == null
          ? null
          : cashReceivedCents - cart.totalCents,
      operationId: 'op_ok_1',
      createdAt: DateTime(2026, 11, 24),
      items: const [],
    );
  }
}

class _SecretThrowingStockRepository extends ClientStorageRepository {
  final String secretPayload;
  final StackTrace fakeStack;
  bool failLookup = true;
  bool failSubmit = false;

  _SecretThrowingStockRepository(
    super.db, {
    required this.secretPayload,
    required this.fakeStack,
  });

  @override
  Future<LocalProduct?> getProductByBarcode(String barcode) async {
    if (failLookup) {
      Error.throwWithStackTrace(
        Exception('Stok barkod hatası: $secretPayload'),
        fakeStack,
      );
    }
    return LocalProduct(
      id: 'prod_stock_1',
      barcode: barcode,
      name: 'Deneme Su',
      price: 1000,
      priceVersionId: 'pv_1',
      stock: 5000,
      stockUnit: 'adet',
      pricingUnit: 'adet',
      conversionFactorNumerator: 1,
      conversionFactorDenominator: 1,
      vatRate: 20,
      isActive: true,
      updatedAt: DateTime(2026, 11, 24),
    );
  }

  @override
  Future<StockReceiptResult> receiveStock({
    required String receiptId,
    required String productId,
    required int quantityMilli,
    int? unitPurchasePrice,
    String? note,
    required String deviceId,
    DateTime? occurredAt,
  }) async {
    if (failSubmit) {
      Error.throwWithStackTrace(
        Exception('Stok kayıt hatası: $secretPayload'),
        fakeStack,
      );
    }
    throw UnimplementedError();
  }
}

class _FailingSystemStatusNotifier extends SystemStatusNotifier {
  final bool syncThrow;
  final String secretPayload;
  final StackTrace fakeStack;

  _FailingSystemStatusNotifier({
    required super.apiClient,
    required super.localDbService,
    required this.syncThrow,
    required this.secretPayload,
    required this.fakeStack,
  }) : super(
          initialStatus: SystemStatus.initial(
            backendUrl: 'https://127.0.0.1:8945',
            deviceId: 'POS-CAT-01',
            localDbPath: ':memory:',
          ),
        );

  @override
  Future<void> refreshLocalMetrics() {
    final err = Exception('Metrics error: $secretPayload');
    if (syncThrow) {
      Error.throwWithStackTrace(err, fakeStack);
    }
    return Future<void>.error(err, fakeStack);
  }
}

class _FakeSyncTransport implements SyncTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FailingSyncCoordinator extends BackgroundSyncCoordinator {
  final bool syncThrow;
  final String secretPayload;
  final StackTrace fakeStack;

  _FailingSyncCoordinator({
    required super.repository,
    required this.syncThrow,
    required this.secretPayload,
    required this.fakeStack,
  }) : super(
          transport: _FakeSyncTransport(),
          deviceId: 'POS-CAT-01',
          readDeviceToken: () => 'tok',
          autoStartTimer: false,
          enableLifecycleListener: false,
        );

  @override
  Future<SyncBatchResult?> triggerSync({
    SyncTriggerReason reason = SyncTriggerReason.manual,
  }) {
    final err = Exception('Sync error: $secretPayload');
    if (syncThrow) {
      Error.throwWithStackTrace(err, fakeStack);
    }
    return Future<SyncBatchResult?>.error(err, fakeStack);
  }
}

class _SecretThrowingHubRepository extends ClientStorageRepository {
  final String secretPayload;
  final StackTrace fakeStack;

  _SecretThrowingHubRepository(
    super.db, {
    required this.secretPayload,
    required this.fakeStack,
  });

  @override
  Future<StoredHubConnection?> getStoredHubConnection({
    required bool allowLoopback,
  }) {
    return Future<StoredHubConnection?>.error(
      Exception('Startup hub error: $secretPayload'),
      fakeStack,
    );
  }
}

class _SecretFailingLocalDbService implements LocalDatabaseService {
  final LocalDatabaseService _delegate;
  @override
  final ClientStorageRepository repository;

  _SecretFailingLocalDbService(this._delegate, this.repository);

  @override
  String get databasePath => _delegate.databasePath;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SecretFailingHubDiscoveryClient implements HubDiscoveryClient {
  final String secretPayload;
  final StackTrace fakeStack;

  _SecretFailingHubDiscoveryClient(this.secretPayload, this.fakeStack);

  @override
  Future<List<DiscoveredHubCandidate>> discover({
    required String deviceId,
    Duration timeout = const Duration(milliseconds: 2500),
    int probeCount = 3,
    Duration probeInterval = const Duration(milliseconds: 600),
  }) {
    return Future<List<DiscoveredHubCandidate>>.error(
      Exception('UDP discovery error: $secretPayload'),
      fakeStack,
    );
  }
}
