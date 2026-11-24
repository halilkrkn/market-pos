import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File clientDbFile;
  late ClientDatabase db;
  late ClientStorageRepository repo;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_b4_ov03_');
    clientDbFile = File(p.join(tempDir.path, 'client_local.db'));
    db = ClientDatabase(clientDbFile);
    repo = ClientStorageRepository(db);
    await repo.initializeDevice('POS-AND-01');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Faz B-4 (OV-03): Hub Restore Sonrası Eksik SYNCED İşlem Uzlaştırması', () {
    test('BK-026: restore_epoch değişimi / HWM gerilemesinde SYNCED işlemler özgün kimlik/payload_hash ile yeniden kuyruğa alınır ve sıfır duplikatla gönderilir', () async {
      await repo.upsertProducts([
        LocalProductsCompanion.insert(
          id: 'p_ov03_1',
          name: 'Süt 1L',
          barcode: const Value('8690001009991'),
          price: 3500,
          stock: 100000,
        ),
      ]);

      // Yerelde 3 satış üret ve başlangıçta epoch_1 altında Hub'a senkronize edilmiş say
      final s1 = await repo.createOfflineSale(
        deviceId: 'POS-AND-01',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('p_ov03_1', 1)],
      );
      final s2 = await repo.createOfflineSale(
        deviceId: 'POS-AND-01',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('p_ov03_1', 1)],
      );
      final s3 = await repo.createOfflineSale(
        deviceId: 'POS-AND-01',
        paymentMethod: 'CARD',
        items: [CartItemInput.units('p_ov03_1', 1)],
      );

      await repo.markOutboxSynced(s1.operationId, clientSeq: s1.clientSeq, deviceId: 'POS-AND-01');
      await repo.markOutboxSynced(s2.operationId, clientSeq: s2.clientSeq, deviceId: 'POS-AND-01');
      await repo.markOutboxSynced(s3.operationId, clientSeq: s3.clientSeq, deviceId: 'POS-AND-01');
      await repo.saveStoredRestoreEpoch('POS-AND-01', 'epoch_1');

      final outboxBefore = await repo.getSyncedOutboxOperations('POS-AND-01');
      expect(outboxBefore.length, equals(3));
      final origOp3Hash = outboxBefore[2].payloadHash;

      // Hub sadece seq=1'in bulunduğu eski yedeğe (epoch_2, HWM=1) geri dönmüş!
      final hubCommittedSeqs = <int>{1};
      final hubOpIds = <String>{s1.operationId};
      var salePostCalls = 0;

      final mockClient = MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'GET' && path == '/api/v1/sync/device-state') {
          final ordered = hubCommittedSeqs.toList()..sort();
          var hwm = 0;
          for (final q in ordered) {
            if (q == hwm + 1) hwm = q;
          }
          return http.Response(
            jsonEncode({
              'device_id': 'POS-AND-01',
              'restore_epoch': 'epoch_2',
              'high_water_mark_seq': hwm,
            }),
            200,
          );
        }
        if (req.method == 'POST' && path == '/api/v1/sync/receipts') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final seqs = List<int>.from(body['client_seqs'] as List);
          return http.Response(
            jsonEncode({
              'restore_epoch': 'epoch_2',
              'receipts': [
                for (final seq in seqs)
                  {
                    'client_seq': seq,
                    'status': hubCommittedSeqs.contains(seq) ? 'FOUND' : 'NOT_FOUND',
                  }
              ],
            }),
            200,
          );
        }
        if (req.method == 'POST' && path == '/api/v1/sales') {
          salePostCalls++;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final seq = body['client_seq'] as int;
          final opId = body['operation_id'] as String;
          hubCommittedSeqs.add(seq);
          hubOpIds.add(opId);
          return http.Response(jsonEncode({'status': 'COMMITTED'}), 201);
        }
        return http.Response('Unexpected ${req.method} $path', 400);
      });

      final syncService = ClientSyncService(
        repository: repo,
        transport: HttpSyncTransport.forStore(
          client: mockClient,
          tenantId: 't1',
          storeId: 's1',
        ),
        deviceId: 'POS-AND-01',
        deviceToken: 'tok_and_1',
        hubUrl: 'https://127.0.0.1:8945',
      );

      final res = await syncService.syncPendingOutbox();
      expect(res.postRestoreHistoryMissing, isFalse);
      expect(res.postRestoreRequeuedCount, equals(2)); // seq 2 & seq 3
      expect(res.syncedCount, equals(2));
      expect(res.isCleanSuccess, isTrue);
      expect(salePostCalls, equals(2));
      expect(hubCommittedSeqs, equals({1, 2, 3}));
      expect(hubOpIds, containsAll([s1.operationId, s2.operationId, s3.operationId]));

      // Özgün payload_hash değiştirilmemiş ve yeni restore_epoch yalnız tamamlanınca kaydedilmiş olmalı
      final afterOps = await repo.getSyncedOutboxOperations('POS-AND-01');
      expect(afterOps[2].operationId, equals(s3.operationId));
      expect(afterOps[2].payloadHash, equals(origOp3Hash));
      expect(await repo.getStoredRestoreEpoch('POS-AND-01'), equals('epoch_2'));
    });

    test('BK-027: Eksik SYNCED işlemin yerel payload/geçmişi yoksa fail-closed durur ve sahte başarı bildirmez', () async {
      await repo.upsertProducts([
        LocalProductsCompanion.insert(
          id: 'p_ov03_2',
          name: 'Ekmek',
          barcode: const Value('8690001009992'),
          price: 1000,
          stock: 100000,
        ),
      ]);

      final s1 = await repo.createOfflineSale(
        deviceId: 'POS-AND-01',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('p_ov03_2', 1)],
      );
      final s2 = await repo.createOfflineSale(
        deviceId: 'POS-AND-01',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('p_ov03_2', 1)],
      );
      await repo.markOutboxSynced(s1.operationId, clientSeq: s1.clientSeq, deviceId: 'POS-AND-01');
      await repo.markOutboxSynced(s2.operationId, clientSeq: s2.clientSeq, deviceId: 'POS-AND-01');
      await repo.saveStoredRestoreEpoch('POS-AND-01', 'epoch_1');

      // s2 yerel Outbox satırı silinmiş / eksik simülasyonu
      await (db.delete(db.outboxOperations)
            ..where((o) => o.operationId.equals(s2.operationId)))
          .go();

      final mockClient = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/api/v1/sync/device-state') {
          return http.Response(
            jsonEncode({
              'device_id': 'POS-AND-01',
              'restore_epoch': 'epoch_2',
              'high_water_mark_seq': 1,
            }),
            200,
          );
        }
        if (req.method == 'POST' && req.url.path == '/api/v1/sync/receipts') {
          return http.Response(
            jsonEncode({
              'restore_epoch': 'epoch_2',
              'receipts': [
                {'client_seq': 2, 'status': 'NOT_FOUND'}
              ],
            }),
            200,
          );
        }
        return http.Response('Not expected', 400);
      });

      final syncService = ClientSyncService(
        repository: repo,
        transport: HttpSyncTransport.forStore(
          client: mockClient,
          tenantId: 't1',
          storeId: 's1',
        ),
        deviceId: 'POS-AND-01',
        deviceToken: 'tok_and_1',
        hubUrl: 'https://127.0.0.1:8945',
      );

      final res = await syncService.syncPendingOutbox();
      expect(res.postRestoreHistoryMissing, isTrue);
      expect(res.isCleanSuccess, isFalse);
      expect(res.lastError, contains('yerel Outbox geçmişi'));
      // Başarısız fail-closed durumda yeni epoch ASLA ileri alınmamalı!
      expect(await repo.getStoredRestoreEpoch('POS-AND-01'), equals('epoch_1'));
    });
  });
}
