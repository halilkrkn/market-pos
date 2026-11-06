import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/storage/local_database_service.dart';
import 'features/diagnostics/application/system_status_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. İstemci Yerel SQLite Veritabanını (client_local.db) Başlat
  final localDbService = await LocalDatabaseService.initialize();

  // 2. Kök Uygulamayı Riverpod ProviderScope ile Başlat
  runApp(
    ProviderScope(
      overrides: [
        localDatabaseServiceProvider.overrideWithValue(localDbService),
      ],
      child: const MarketPosApp(),
    ),
  );
}
