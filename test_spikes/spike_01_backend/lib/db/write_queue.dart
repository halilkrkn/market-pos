import 'dart:async';
import 'package:sqlite3/sqlite3.dart';

class ServiceDrainingException implements Exception {
  final String message;
  ServiceDrainingException(
      [this.message = 'Servis kapanıyor, yeni yazma isteği kabul edilmiyor.']);
  @override
  String toString() => 'ServiceDrainingException: $message';
}

class WriteQueueMetrics {
  int totalEnqueued = 0;
  int totalCompleted = 0;
  int totalFailed = 0;
  int totalRetries = 0;
  int totalBusyErrors = 0;
  int currentQueueLength = 0;
  int peakQueueLength = 0;

  Map<String, dynamic> toJson() => {
        'total_enqueued': totalEnqueued,
        'total_completed': totalCompleted,
        'total_failed': totalFailed,
        'total_retries': totalRetries,
        'total_busy_errors': totalBusyErrors,
        'current_queue_length': currentQueueLength,
        'peak_queue_length': peakQueueLength,
      };
}

class WriteQueue {
  final WriteQueueMetrics metrics = WriteQueueMetrics();
  final int maxRetries;
  final Duration initialRetryDelay;
  bool _isDraining = false;
  Future<void> _lastTask = Future.value();

  WriteQueue({
    this.maxRetries = 3,
    this.initialRetryDelay = const Duration(milliseconds: 50),
  });

  bool get isDraining => _isDraining;

  /// Kuyruğu boşaltma moduna alır (yeni iş kabulünü hemen durdurur).
  void markDraining() {
    _isDraining = true;
  }

  Future<T> enqueue<T>(
    Future<T> Function() operation, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (_isDraining) {
      throw ServiceDrainingException();
    }

    metrics.totalEnqueued++;
    metrics.currentQueueLength++;
    if (metrics.currentQueueLength > metrics.peakQueueLength) {
      metrics.peakQueueLength = metrics.currentQueueLength;
    }

    final completer = Completer<T>();

    _lastTask = _lastTask.then((_) async {
      try {
        final result = await _executeWithRetry(operation).timeout(timeout);
        metrics.totalCompleted++;
        completer.complete(result);
      } catch (e, st) {
        metrics.totalFailed++;
        completer.completeError(e, st);
      } finally {
        metrics.currentQueueLength--;
      }
    });

    return completer.future;
  }

  Future<T> _executeWithRetry<T>(Future<T> Function() operation) async {
    int attempts = 0;
    Duration currentDelay = initialRetryDelay;

    while (true) {
      try {
        attempts++;
        return await operation();
      } on SqliteException catch (e) {
        // SQLite Error 5: SQLITE_BUSY
        if (e.extendedResultCode == 5 || e.resultCode == 5) {
          metrics.totalBusyErrors++;
          if (attempts <= maxRetries) {
            metrics.totalRetries++;
            await Future.delayed(currentDelay);
            currentDelay = currentDelay * 2; // exponential backoff
            continue;
          }
        }
        rethrow;
      }
    }
  }

  /// Servis kapatılırken yeni istek alımını durdurur ve mevcut kuyruğun bitmesini bekler.
  /// S5A-2: Başarıyla boşaltıldıysa `true`, zaman aşımı durumunda `false` döner.
  /// Maksimum varsayılan drain süresi 12 saniyedir.
  Future<bool> drain({Duration timeout = const Duration(seconds: 12)}) async {
    _isDraining = true;
    if (timeout <= Duration.zero) return false;
    try {
      await _lastTask.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      // Kuyruk zincirindeki bireysel işlem hataları drain işlemini başarısız saydırmaz
      return true;
    }
  }

  /// S5A-4: Bakım / restore işlemi için kuyruğu duraklatır ve mevcut işlerin bitmesini bekler.
  Future<bool> pauseForMaintenance({Duration timeout = const Duration(seconds: 10)}) async {
    _isDraining = true;
    if (timeout <= Duration.zero) return false;
    try {
      await _lastTask.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      return true;
    }
  }

  /// S5A-4: Bakım / restore tamamlandığında kuyruğu yeniden iş alımına açar.
  void resumeAfterMaintenance() {
    _isDraining = false;
    _lastTask = Future.value();
  }
}
