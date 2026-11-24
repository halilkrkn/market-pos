import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  String repoRootPath() {
    final cwd = Directory.current.path;
    if (File(p.join(cwd, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(cwd, 'lib')).existsSync()) {
      return cwd;
    }
    return Directory.current.parent.path;
  }

  List<String> extractPublicMembersOfClientStorageRepository(String source) {
    final startIdx = source.indexOf('class ClientStorageRepository');
    expect(startIdx, greaterThanOrEqualTo(0));
    final openBrace = source.indexOf('{', startIdx);
    var depth = 0;
    final members = <String>{};
    final lines = source.substring(openBrace).split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final stripped = line.replaceAll(RegExp(r'//.*$'), '');
      if (depth == 1 &&
          RegExp(r'^  (?!static\b)(?:Future<|Stream<|void\s|int\s|bool\s|String\s|ClientDatabase\s)')
              .hasMatch(stripped)) {
        var sig = stripped.trim();
        var j = i + 1;
        while (j < lines.length && !sig.contains(RegExp(r'[\(\{;]'))) {
          sig += ' ${lines[j].trim()}';
          j++;
        }
        final getMatch =
            RegExp(r'\bget\s+([a-zA-Z_][a-zA-Z0-9_]*)\b').firstMatch(sig);
        if (getMatch != null) {
          final name = getMatch.group(1)!;
          if (!name.startsWith('_')) members.add(name);
        } else {
          final fnMatch = RegExp(
            r'([a-zA-Z_][a-zA-Z0-9_]*)\s*(?:<[^>]*>)?\s*\(',
          ).firstMatch(sig);
          if (fnMatch != null) {
            final name = fnMatch.group(1)!;
            if (!name.startsWith('_') && name != 'ClientStorageRepository') {
              members.add(name);
            }
          }
        }
      }
      depth += '{'.allMatches(stripped).length;
      depth -= '}'.allMatches(stripped).length;
      if (i > 0 && depth <= 0) break;
    }
    return members.toList()..sort();
  }

  group('AUD-MED-06: Clean Architecture & Repository Sınırları', () {
    test(
      '1. _TrackedClientStorageRepository, ClientStorageRepository üzerindeki tüm açık metotları (getRefundTotalsBySaleIds dahil) override etmelidir',
      () {
        final root = repoRootPath();
        final repoFile = File(
          p.join(
            root,
            'packages',
            'mms_client_storage',
            'lib',
            'src',
            'database',
            'client_storage_repository.dart',
          ),
        );
        final trackedFile = File(
          p.join(root, 'lib', 'core', 'storage', 'local_database_service.dart'),
        );

        final repoMembers = extractPublicMembersOfClientStorageRepository(
          repoFile.readAsStringSync(),
        );
        final trackedSrc = trackedFile.readAsStringSync();
        final trackedSection = trackedSrc.substring(
          trackedSrc.indexOf('class _TrackedClientStorageRepository'),
        );

        expect(repoMembers, contains('getRefundTotalsBySaleIds'));

        final missing = <String>[];
        for (final member in repoMembers) {
          final overridePattern = RegExp(
            '@override[\\s\\S]{0,180}\\b${RegExp.escape(member)}\\s*[\\(<;=]',
          );
          if (!overridePattern.hasMatch(trackedSection)) {
            missing.add(member);
          }
        }

        expect(
          missing,
          isEmpty,
          reason:
              'Drain/close güvenliğini atlayan override edilmemiş ClientStorageRepository metotları: $missing',
        );
      },
    );

    test(
      '2. getRefundTotalsBySaleIds kapalı bağlantıda DatabaseClosedException fırlatmalı ve restore rebind ile çalışmalıdır',
      () async {
        final tempDir =
            Directory.systemTemp.createTempSync('mms_test_only_med06_repo_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final dbPath = p.join(tempDir.path, 'client_local.db');
        final svc = await LocalDatabaseService.initialize(customPath: dbPath);
        addTearDown(() async {
          if (!svc.isClosed) {
            await svc.close();
          }
          await LocalDatabaseService.closeActive();
          LocalDatabaseService.resetForTesting();
        });

        await svc.database.into(svc.database.localSales).insert(
              LocalSalesCompanion.insert(
                id: 'sale_med06_1',
                deviceId: 'DEV-MED06',
                clientSeq: 1,
                paymentMethod: 'CASH',
                totalAmount: 5000,
                status: const Value('PARTIALLY_REFUNDED'),
              ),
            );
        await svc.database.into(svc.database.localRefunds).insert(
              LocalRefundsCompanion.insert(
                id: 'ref_med06_1',
                saleId: 'sale_med06_1',
                deviceId: 'DEV-MED06',
                clientSeq: 2,
                totalRefundAmount: 1500,
                paymentMethod: 'CASH',
                reason: 'Hasarlı',
                createdAt: Value(DateTime.now().toUtc()),
              ),
            );

        final trackedRepo = svc.repository;
        final initialTotals =
            await trackedRepo.getRefundTotalsBySaleIds(['sale_med06_1']);
        expect(initialTotals, equals({'sale_med06_1': 1500}));

        // restore sırasında rebind sonrası da delegasyon korunmalı
        await svc.suspendForRestore();
        await svc.resumeAfterRestore();
        final afterRestoreTotals =
            await trackedRepo.getRefundTotalsBySaleIds(['sale_med06_1']);
        expect(afterRestoreTotals, equals({'sale_med06_1': 1500}));

        // Close sonrası tüm repository çağrıları gibi getRefundTotalsBySaleIds de doğrudan trackedRepo üzerinden fail-closed olmalıdır
        await svc.close();
        await expectLater(
          trackedRepo.getRefundTotalsBySaleIds(['sale_med06_1']),
          throwsA(isA<DatabaseClosedException>()),
        );
      },
    );

    test(
      '3. Tüm feature domain dosyaları Flutter framework ve data/presentation/TLS IO bağımlılıklarından arındırılmış olmalıdır',
      () {
        final root = repoRootPath();
        final featuresDir = Directory(p.join(root, 'lib', 'features'));
        final domainFiles = featuresDir
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.dart') &&
                  RegExp(r'[\\/]domain[\\/]').hasMatch(f.path),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

        expect(domainFiles, isNotEmpty);
        final violations = <String>[];

        for (final file in domainFiles) {
          final rel = p.relative(file.path, from: root).replaceAll('\\', '/');
          for (final line in file.readAsLinesSync()) {
            final trimmed = line.trim();
            if (!trimmed.startsWith('import ')) continue;
            if (trimmed.contains('package:flutter/') ||
                trimmed.contains('package:drift/') ||
                trimmed.contains('dart:io') ||
                trimmed.contains('/data/') ||
                trimmed.contains('/presentation/') ||
                trimmed.contains('tls_pinned_client_factory.dart')) {
              violations.add('$rel -> $trimmed');
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason: 'Domain katmanı sınır ihlalleri bulundu: $violations',
        );
      },
    );

    test(
      '4. CatalogNotifier data katmanına doğrudan bağlanmaz; DiagnosticsView doğrudan veritabanı servisine erişmez; döngüsel paket bağımlılığı yoktur',
      () {
        final root = repoRootPath();

        final catalogNotifierFile = File(
          p.join(
            root,
            'lib',
            'features',
            'catalog',
            'application',
            'catalog_notifier.dart',
          ),
        );
        final catalogSrc = catalogNotifierFile.readAsStringSync();
        expect(
          catalogSrc.contains('../data/'),
          isFalse,
          reason:
              'Application katmanı CatalogNotifier somut data katmanına değil domain CatalogRepository sözleşmesine bağlanmalıdır.',
        );

        final diagnosticsViewFile = File(
          p.join(
            root,
            'lib',
            'features',
            'diagnostics',
            'presentation',
            'screens',
            'diagnostics_view.dart',
          ),
        );
        final diagSrc = diagnosticsViewFile.readAsStringSync();
        expect(
          diagSrc.contains('local_database_service.dart'),
          isFalse,
          reason:
              'Presentation ekranı DiagnosticsView doğrudan LocalDatabaseService import etmemelidir.',
        );
        expect(
          diagSrc.contains('package:mms_client_storage/'),
          isFalse,
          reason:
              'Presentation ekranı DiagnosticsView doğrudan storage paketine değil domain/application servisine bağlanmalıdır.',
        );

        // Paket bağımlılık yönü (döngüsel bağımlılık engeli):
        // mms_contracts -> yok; mms_client_storage -> mms_contracts; market_pos -> mms_client_storage + mms_contracts
        final contractsPubspec = File(
          p.join(root, 'packages', 'mms_contracts', 'pubspec.yaml'),
        ).readAsStringSync();
        final storagePubspec = File(
          p.join(root, 'packages', 'mms_client_storage', 'pubspec.yaml'),
        ).readAsStringSync();
        expect(contractsPubspec.contains('mms_client_storage'), isFalse);
        expect(contractsPubspec.contains('market_pos'), isFalse);
        expect(storagePubspec.contains('market_pos'), isFalse);
      },
    );
  });
}
