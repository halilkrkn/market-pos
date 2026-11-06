import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';

/// S5A-2: Servis kapanırken yeni istekleri anında 503 reddeden ve
/// devam etmekte olan (in-flight) isteklerin kontrollü tamamlanmasını izleyen kapı mekanizması.
class AdmissionGate {
  bool _isOpen = true;
  int _inFlightRequests = 0;
  Completer<void>? _drainCompleter;

  bool get isOpen => _isOpen;
  int get inFlightRequests => _inFlightRequests;

  /// Yeni bir HTTP isteği kabul edilmeye çalışılır.
  /// Kapı açıksa `true` döner ve in-flight sayacı atomik artırılır.
  /// Kapı kapalıysa (draining) derhal `false` döner.
  bool tryAcquire() {
    if (!_isOpen) return false;
    _inFlightRequests++;
    return true;
  }

  /// İstek tamamlandığında in-flight sayacı düşürülür.
  void release() {
    if (_inFlightRequests > 0) {
      _inFlightRequests--;
    }
    if (!_isOpen && _inFlightRequests == 0 && _drainCompleter != null && !_drainCompleter!.isCompleted) {
      _drainCompleter!.complete();
    }
  }

  /// Kapıyı yeni isteklere kapatır. Artık `tryAcquire()` derhal false döner.
  void close() {
    _isOpen = false;
    if (_inFlightRequests == 0 && _drainCompleter != null && !_drainCompleter!.isCompleted) {
      _drainCompleter!.complete();
    }
  }

  /// Devam etmekte olan (in-flight) isteklerin bitmesini bekler.
  /// Süre dolmadan tamamlanırsa `true`, zaman aşımına uğrarsa `false` döner.
  Future<bool> waitForInFlightDrain({Duration timeout = const Duration(seconds: 12)}) async {
    if (_inFlightRequests == 0) return true;
    if (timeout <= Duration.zero) return false;
    _drainCompleter ??= Completer<void>();
    try {
      await _drainCompleter!.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  /// Testler için durumu sıfırlar.
  void reset() {
    _isOpen = true;
    _inFlightRequests = 0;
    _drainCompleter = null;
  }

  /// S5A-4: Bakım / restore işlemi için yeni istekleri durdurur ve mevcut restore isteği dışındaki isteklerin drain olmasını bekler.
  Future<bool> pauseForMaintenance({int allowedRemaining = 1, Duration timeout = const Duration(seconds: 10)}) async {
    _isOpen = false;
    if (_inFlightRequests <= allowedRemaining) return true;
    final stopwatch = Stopwatch()..start();
    while (_inFlightRequests > allowedRemaining) {
      if (stopwatch.elapsed >= timeout) return false;
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return true;
  }

  /// S5A-4: Bakım / restore tamamlandığında kapıyı normal API isteklerine yeniden açar.
  void resumeAfterMaintenance() {
    _isOpen = true;
    _drainCompleter = null;
  }
}

/// S5A-2: Shelf pipeline middleware'i.
/// Kapı kapalıysa istekleri 503 Service Unavailable / Draining ile reddeder.
Middleware createAdmissionMiddleware(AdmissionGate gate) {
  return (Handler innerHandler) {
    return (Request request) async {
      if (!gate.tryAcquire()) {
        return Response(
          503,
          body: jsonEncode({
            'error': 'SERVICE_DRAINING',
            'code': 'ERR_SERVICE_DRAINING',
            'message': 'Windows Service kapanıyor, yeni istek kabul edilmiyor.',
          }),
          headers: {
            'content-type': 'application/json',
            'retry-after': '5',
          },
        );
      }

      try {
        return await innerHandler(request);
      } finally {
        gate.release();
      }
    };
  };
}

