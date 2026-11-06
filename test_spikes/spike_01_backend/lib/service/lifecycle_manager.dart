import 'dart:async';
import 'dart:io';
import '../db/database.dart';
import '../db/write_queue.dart';
import 'admission_gate.dart';

class LifecycleManager {
  SpikeDatabase db;
  final WriteQueue writeQueue;
  final AdmissionGate admissionGate;
  final Duration drainTimeout;
  CheckpointResult? lastCheckpointResult;
  HttpServer? _server;
  final Completer<int> _shutdownCompleter = Completer<int>();
  bool _isShuttingDown = false;
  int _exitCode = 0;
  StreamSubscription<ProcessSignal>? _sigintSub;
  StreamSubscription<ProcessSignal>? _sigtermSub;

  LifecycleManager({
    required this.db,
    required this.writeQueue,
    AdmissionGate? admissionGate,
    this.drainTimeout = const Duration(seconds: 12),
  }) : admissionGate = admissionGate ?? AdmissionGate();

  void attachServer(HttpServer server) {
    _server = server;
    _setupSignalListeners();
  }

  bool get isShuttingDown => _isShuttingDown;
  int get exitCode => _exitCode;
  Future<void> get onShutdown => _shutdownCompleter.future;

  void _setupSignalListeners() {
    // Windows'ta ProcessSignal.sigterm desteklenmeyebilir; sigint her iki OS'ta da çalışır.
    _sigintSub = ProcessSignal.sigint.watch().listen((_) {
      shutdown(reason: 'SIGINT received (Ctrl+C / WinSW Stop)', exitProcess: true);
    });
    if (!Platform.isWindows) {
      _sigtermSub = ProcessSignal.sigterm.watch().listen((_) {
        shutdown(reason: 'SIGTERM received', exitProcess: true);
      });
    }
  }

  /// S5A-2: Kontrollü ve güvenli kapatma akışı (Tekil Global Deadline ile):
  /// 1. AdmissionGate kapatılır (yeni istekler anında 503 Draining alır).
  /// 2. HttpServer.close(force: false) çağrılır (mevcut bağlantıların yanıt vermesi için izin verilir).
  /// 3. In-flight HTTP isteklerinin tamamlanması beklenir (Global deadline'dan kalan süreyle).
  /// 4. WriteQueue.drain çalıştırılır (Global deadline'dan kalan süreyle, maksimum toplam 12 sn).
  /// 5. Drain başarılıysa:
  ///    - PRAGMA wal_checkpoint(TRUNCATE) tetiklenir ve busy/log/checkpointed incelenir.
  ///    - SQLite bağlantısı kapatılır (db.close()).
  ///    - HttpServer force close ile kalan açık soketler temizlenir.
  ///    - 0 kodu ile tamamlanır.
  /// 6. Drain zaman aşımına uğrarsa (12s limit):
  ///    - Veritabanı KESİNLİKLE kapatılmaz (db.close() çağrılmaz).
  ///    - WAL checkpoint ÇALIŞTIRILMAZ (veriler WAL dosyasında korunur).
  ///    - HttpServer force close yapılır.
  ///    - 101 çıkış kodu ile tamamlanır.
  Future<int> shutdown({
    String reason = 'Normal shutdown',
    bool exitProcess = false,
  }) async {
    if (_isShuttingDown) return _shutdownCompleter.future;
    _isShuttingDown = true;

    final stopwatch = Stopwatch()..start();
    Duration getRemaining() {
      final elapsed = stopwatch.elapsed;
      if (elapsed >= drainTimeout) return Duration.zero;
      return drainTimeout - elapsed;
    }

    // 1. AdmissionGate kapatılır ve yazma kuyruğu yeni iş alımına durdurulur
    admissionGate.close();
    writeQueue.markDraining();

    // Sinyal aboneliklerini hemen iptal et
    await _sigintSub?.cancel();
    _sigintSub = null;
    await _sigtermSub?.cancel();
    _sigtermSub = null;

    // 2. HTTP sunucusunu zarif biçimde kapat (yeni bağlantı kabul etme, mevcuda izin ver)
    if (_server != null) {
      try {
        await _server!.close(force: false);
      } catch (_) {}
    }

    // 3. In-flight HTTP isteklerinin tamamlanmasını bekle (Global deadline kalan süresi)
    final inFlightOk = await admissionGate.waitForInFlightDrain(timeout: getRemaining());

    // 4. Yazma kuyruğunu dondur ve devam edenlerin bitmesini bekle (Global deadline kalan süresi)
    final remainingForWriteQueue = getRemaining();
    final drainSuccess = (inFlightOk && remainingForWriteQueue > Duration.zero)
        ? await writeQueue.drain(timeout: remainingForWriteQueue)
        : false;

    if (drainSuccess) {
      // 5. Drain başarılı:
      // PRAGMA wal_checkpoint(TRUNCATE) tetiklenir ve sonuç incelenir
      try {
        lastCheckpointResult = await db.checkpointWal(mode: 'TRUNCATE');
      } catch (e) {
        stderr.writeln('[WARN] WAL checkpoint exception: $e');
        lastCheckpointResult = const CheckpointResult(busy: 1, log: -1, checkpointed: -1);
      }

      if (lastCheckpointResult != null && !lastCheckpointResult!.isSuccess) {
        stderr.writeln(
          '[WARN] WAL checkpoint BUSY: $lastCheckpointResult. '
          'Veriler WAL dosyasında korunarak DB güvenle kapatılıyor, recovery açılışta sağlanacak.',
        );
      }

      // Veritabanını güvenle kapat
      try {
        await db.close();
      } catch (_) {}

      // Kalan soket varsa force close
      if (_server != null) {
        try {
          await _server!.close(force: true);
        } catch (_) {}
      }

      _exitCode = 0;
    } else {
      // 6. Drain zaman aşımına uğrarsa (12 saniyelik global limit aşıldı):
      // Veritabanı KESİNLİKLE kapatılmaz (db.close() çağrılmaz)
      // WAL checkpoint ÇALIŞTIRILMAZ (veriler WAL dosyasında korunur)
      if (_server != null) {
        try {
          await _server!.close(force: true);
        } catch (_) {}
      }

      _exitCode = 101;
    }

    if (!_shutdownCompleter.isCompleted) {
      _shutdownCompleter.complete(_exitCode);
    }

    if (exitProcess) {
      exit(_exitCode);
    }

    return _exitCode;
  }
}
