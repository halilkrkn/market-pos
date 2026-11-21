import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/app_destination.dart';

/// MARKET MMS aktif modül navigasyon durumu.
///
/// Seçenek A mimari kararı gereği ek paket eklenmeden tipli [AppDestination]
/// enumu üzerinden Riverpod ile yönetilir.
final activeDestinationProvider = StateProvider<AppDestination>(
  (ref) => AppDestination.pos,
);
