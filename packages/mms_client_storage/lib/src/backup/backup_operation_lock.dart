import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'database_backup_engine.dart';

/// Kilitli işlemin türü (kullanıcı mesajında ve kilit dosyasında görünür).
enum BackupOperationKind {
  backup('BACKUP', 'yedekleme'),
  restore('RESTORE', 'geri yükleme');

  final String value;
  final String label;
  const BackupOperationKind(this.value, this.label);

  static BackupOperationKind? tryParse(Object? raw) {
    for (final kind in values) {
      if (kind.value == raw) return kind;
    }
    return null;
  }
}

/// BK-LOCK — Aynı yedek dizininde aynı anda tek yedek/restore işlemi.
///
/// Kilit, dosyanın özel (`exclusive: true`) oluşturulmasına dayanır; bu nedenle
/// aynı süreçteki farklı isolate'ler (ör. ön plan zamanlayıcısı ve arka plan
/// işçisi) ile farklı işletim sistemi süreçleri arasında geçerlidir.
///
/// Güvenilirlik modeli (ADR-016):
/// - Aktif kilit sahibi işlem sürdükçe periyodik olarak ([heartbeatInterval])
///   `heartbeat_at` zaman damgasını atomik olarak yeniler; böylece uzun süren
///   PBKDF2/restore işlemleri yanlışlıkla stale kabul edilmez.
/// - Süreç ani çökerse heartbeat durur ve kilit [staleAfter] (varsayılan 60 sn)
///   sonunda devralınabilir hale gelir.
/// - Eski kilidi devralma işlemi ayrı bir `.recovering` kilidi altında
///   çift doğrulama (owner token + tazelik kontrolü) ile yürütülerek TOCTOU
///   yarış koşulları önlenir; aktif başka bir sürecin canlı kilidi silinemez.
class BackupOperationLock {
  static const String defaultFileName = '.mms_backup_operation.lock';
  static const String busyErrorCode = 'ERR_BACKUP_OPERATION_BUSY';

  final File file;
  final Duration staleAfter;
  final Duration heartbeatInterval;
  final Duration recoveryLockStaleAfter;
  final Duration emptyLockStaleAfter;
  final DateTime Function() clock;

  static final Random _random = Random.secure();

  BackupOperationLock(
    this.file, {
    this.staleAfter = const Duration(seconds: 60),
    this.heartbeatInterval = const Duration(seconds: 10),
    this.recoveryLockStaleAfter = const Duration(seconds: 30),
    this.emptyLockStaleAfter = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());

  /// [action] süresince kilidi tutar; hata olsa da kilit bırakılır.
  Future<T> synchronized<T>(BackupOperationKind kind, Future<T> Function() action) async {
    final held = await acquire(kind);
    try {
      return await action();
    } finally {
      await held.release();
    }
  }

  /// Kilidi alır; başka bir işlem sürüyorsa [busyErrorCode] ile [BackupException] fırlatır.
  Future<HeldBackupOperationLock> acquire(BackupOperationKind kind) async {
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final token = _generateToken();
    final now = clock().toUtc();
    final content = _encodeLockJson(
      kind: kind,
      token: token,
      acquiredAt: now,
      heartbeatAt: now,
    );

    // Çakışma/kurtarma/boş dosya yarışlarında sınırlı yeniden deneme.
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await file.create(exclusive: true);
        await file.writeAsString(content, flush: true);
        return HeldBackupOperationLock._(
          file: file,
          kind: kind,
          token: token,
          acquiredAt: now,
          staleAfter: staleAfter,
          heartbeatInterval: heartbeatInterval,
          clock: clock,
        );
      } on FileSystemException {
        var holder = await _readHolder();
        if (holder == null) {
          // Kilit tam o anda bırakıldı; bir sonraki denemede almayı dene.
          continue;
        }
        if (holder.isEmpty && attempt == 0) {
          // Başka süreç tam `create` ile `writeAsString` arasında olabilir; kısa bekle ve yeniden oku.
          await Future<void>.delayed(const Duration(milliseconds: 25));
          holder = await _readHolder();
          if (holder == null) continue;
        }

        if (_isStale(holder)) {
          final recovered = await _recoverStaleAndAcquire(
            staleHolder: holder,
            kind: kind,
            token: token,
            now: now,
            content: content,
          );
          if (recovered != null) {
            return recovered;
          }
          // Başka süreç kurtarmayı veya yenilemeyi tamamladı; güncel tutucuyu tekrar değerlendir.
          final current = await _readHolder();
          if (current != null && !_isStale(current)) {
            _throwBusy(current);
          }
          continue;
        }

        _throwBusy(holder);
      }
    }

    final current = await _readHolder();
    if (current != null) {
      _throwBusy(current);
    }
    throw const BackupException(
      busyErrorCode,
      'Yedekleme kilidi alınamadı; birkaç saniye sonra tekrar deneyin.',
    );
  }

  Never _throwBusy(_LockHolder holder) {
    final busyLabel = holder.kind?.label ?? 'yedekleme/geri yükleme';
    throw BackupException(
      busyErrorCode,
      'Şu anda başka bir $busyLabel işlemi sürüyor. İşlem bitince tekrar deneyin.',
    );
  }

  bool _isStale(_LockHolder holder) {
    final limit = holder.isEmpty ? emptyLockStaleAfter : staleAfter;
    return clock().toUtc().difference(holder.heartbeatAt) > limit;
  }

  Future<_LockHolder?> _readHolder() async {
    for (var i = 0; i < 3; i++) {
      try {
        final raw = await file.readAsString();
        final modified = (await file.lastModified()).toUtc();
        if (raw.trim().isEmpty) {
          return _LockHolder(
            raw: raw,
            token: null,
            kind: null,
            heartbeatAt: modified,
            isEmpty: true,
          );
        }
        final corrupt = _LockHolder(
          raw: raw,
          token: null,
          kind: null,
          heartbeatAt: modified,
        );
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final acquiredStr = json['acquired_at'] as String?;
          final heartbeatStr = json['heartbeat_at'] as String?;
          final effectiveTs = DateTime.parse(heartbeatStr ?? acquiredStr!).toUtc();
          final tokenRaw = json['token'] ?? json['owner_id'];
          return _LockHolder(
            raw: raw,
            token: tokenRaw is String && tokenRaw.isNotEmpty ? tokenRaw : null,
            kind: BackupOperationKind.tryParse(json['operation']),
            heartbeatAt: effectiveTs,
          );
        } on FormatException {
          return corrupt;
        } on TypeError {
          return corrupt;
        }
      } on FileSystemException catch (e) {
        if (!await file.exists()) {
          return null;
        }
        // Windows kısa süreli rename/paylaşım çakışması: hemen pes etme.
        if (i < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 15));
          continue;
        }
        return _LockHolder(
          raw: e.message,
          token: null,
          kind: null,
          heartbeatAt: clock().toUtc(),
        );
      }
    }
    return null;
  }

  /// TOCTOU-güvenli eski kilit kurtarma: sahip belirteçli `.recovering` kilidi altında
  /// sahibinin değişmediğini ve hâlâ stale olduğunu doğruladıktan sonra
  /// eski kilidi siler ve yeni kilidi atomik olarak oluşturur.
  Future<HeldBackupOperationLock?> _recoverStaleAndAcquire({
    required _LockHolder staleHolder,
    required BackupOperationKind kind,
    required String token,
    required DateTime now,
    required String content,
  }) async {
    final recoveryFile = File('${file.path}.recovering');
    final recoveryToken = await _acquireRecoveryMutex(recoveryFile);
    if (recoveryToken == null) {
      // Başka bir süreç şu anda kurtarma yürütüyor; kısa süre bekleyip kontrol edilir.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return null;
    }

    try {
      final current = await _readHolder();
      if (current != null) {
        final sameOwner = (staleHolder.token != null && current.token != null)
            ? current.token == staleHolder.token
            : current.raw == staleHolder.raw;
        if (!sameOwner || !_isStale(current)) {
          // Aktif sahip heartbeat attı veya başka süreç zaten devraldı -> DOKUNMA!
          return null;
        }
        await file.delete();
        stderr.writeln(
          '[BackupLock] Eski kilit devralındı (${current.kind?.value ?? 'BİLİNMEYEN'}, '
          'son nabız: ${current.heartbeatAt.toIso8601String()}).',
        );
      }

      try {
        await file.create(exclusive: true);
        await file.writeAsString(content, flush: true);
        return HeldBackupOperationLock._(
          file: file,
          kind: kind,
          token: token,
          acquiredAt: now,
          staleAfter: staleAfter,
          heartbeatInterval: heartbeatInterval,
          clock: clock,
        );
      } on FileSystemException {
        // Tam kurtarma penceresinde başka normal alıcı oluşturdu -> kaybettik.
        return null;
      }
    } on FileSystemException catch (e) {
      stderr.writeln('[BackupLock] Eski kilit kurtarılamadı: ${e.message}');
      return null;
    } finally {
      await _releaseRecoveryMutex(recoveryFile, recoveryToken);
    }
  }

  Future<({String? token, DateTime createdAt})?> _readRecoveryState(
    File recoveryFile,
  ) async {
    try {
      final raw = await recoveryFile.readAsString();
      final modified = (await recoveryFile.lastModified()).toUtc();
      if (raw.trim().isEmpty) {
        return (token: null, createdAt: modified);
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final token = decoded['token'] as String?;
        final tsRaw = decoded['created_at'] as String?;
        final parsedTs = tsRaw != null ? DateTime.tryParse(tsRaw)?.toUtc() : null;
        return (
          token: token != null && token.isNotEmpty ? token : null,
          createdAt: parsedTs ?? modified,
        );
      }
      return (token: null, createdAt: modified);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<String?> _acquireRecoveryMutex(File recoveryFile) async {
    final myToken = _generateToken();
    for (var i = 0; i < 3; i++) {
      try {
        await recoveryFile.create(exclusive: true);
        await recoveryFile.writeAsString(
          jsonEncode({
            'token': myToken,
            'created_at': clock().toUtc().toIso8601String(),
          }),
          flush: true,
        );
        return myToken;
      } on FileSystemException {
        try {
          if (!await recoveryFile.exists()) continue;
          var state = await _readRecoveryState(recoveryFile);
          if (state == null) {
            await Future<void>.delayed(const Duration(milliseconds: 15));
            if (!await recoveryFile.exists()) continue;
            state = (
              token: null,
              createdAt: (await recoveryFile.lastModified()).toUtc(),
            );
          }
          if (state.token == null && i == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            state = await _readRecoveryState(recoveryFile) ?? state;
          }
          final effectiveThreshold = state.token == null &&
                  emptyLockStaleAfter < recoveryLockStaleAfter
              ? emptyLockStaleAfter
              : recoveryLockStaleAfter;
          final age = clock().toUtc().difference(state.createdAt);
          if (age > effectiveThreshold) {
            final recheck = await _readRecoveryState(recoveryFile);
            if (recheck == null || recheck.token != state.token) {
              // Başka süreç tam şu anda devraldı; taze kilidi ASLA silme!
              return null;
            }
            if (await recoveryFile.exists()) {
              await recoveryFile.delete();
            }
            continue;
          }
        } on FileSystemException {
          // Başka süreç sildi/oluşturdu; tekrar dene.
          continue;
        }
        return null;
      }
    }
    return null;
  }

  static Future<void> _releaseRecoveryMutex(
    File recoveryFile,
    String expectedToken,
  ) async {
    try {
      if (!await recoveryFile.exists()) return;
      final raw = await recoveryFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded['token'] == expectedToken) {
        await recoveryFile.delete();
      }
    } catch (_) {
      // Yoksa veya başkasına geçtiyse dokunma.
    }
  }

  static String _generateToken() {
    return List<int>.generate(16, (_) => _random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String _encodeLockJson({
    required BackupOperationKind kind,
    required String token,
    required DateTime acquiredAt,
    required DateTime heartbeatAt,
  }) {
    return jsonEncode({
      'version': 2,
      'operation': kind.value,
      'pid': pid,
      'owner_id': token,
      'token': token,
      'acquired_at': acquiredAt.toUtc().toIso8601String(),
      'heartbeat_at': heartbeatAt.toUtc().toIso8601String(),
    });
  }

  static Future<void> _deleteFileQuietly(File target) async {
    try {
      if (await target.exists()) {
        await target.delete();
      }
    } on FileSystemException catch (e) {
      stderr.writeln('[BackupLock] Geçici kurtarma dosyası silinemedi: ${e.message}');
    }
  }
}

class _LockHolder {
  final String raw;
  final String? token;
  final BackupOperationKind? kind;
  final DateTime heartbeatAt;
  final bool isEmpty;

  const _LockHolder({
    required this.raw,
    required this.token,
    required this.kind,
    required this.heartbeatAt,
    this.isEmpty = false,
  });
}

/// Alınmış kilit. Aktif olduğu sürece heartbeat ile süreyi uzatır; [release]
/// yalnızca bu kilidin belirtecini taşıyan dosyayı siler.
class HeldBackupOperationLock {
  final File _file;
  final BackupOperationKind _kind;
  final String _token;
  final DateTime _acquiredAt;
  final Duration _staleAfter;
  final DateTime Function() _clock;

  DateTime _lastHeartbeatAt;
  Timer? _heartbeatTimer;
  Future<bool>? _pendingBeat;
  bool _released = false;
  bool _lostOwnership = false;
  int _consecutiveBeatErrors = 0;

  HeldBackupOperationLock._({
    required File file,
    required BackupOperationKind kind,
    required String token,
    required DateTime acquiredAt,
    required Duration staleAfter,
    required Duration heartbeatInterval,
    required DateTime Function() clock,
  })  : _file = file,
        _kind = kind,
        _token = token,
        _acquiredAt = acquiredAt,
        _staleAfter = staleAfter,
        _clock = clock,
        _lastHeartbeatAt = acquiredAt {
    if (heartbeatInterval > Duration.zero) {
      _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
        unawaited(heartbeatNow());
      });
    }
  }

  String get ownerToken => _token;
  bool get isReleased => _released;
  bool get lostOwnership => _lostOwnership;

  /// Kilit sahipliğini doğrular ve `heartbeat_at` damgasını atomik olarak yeniler.
  /// Sahiplik kaybedilmişse `false` döner ve dosyaya dokunmaz.
  Future<bool> heartbeatNow() {
    if (_released || _lostOwnership) return Future<bool>.value(false);
    final inflight = _pendingBeat;
    if (inflight != null) return inflight;

    final future = _beat();
    _pendingBeat = future;
    return future.whenComplete(() {
      if (identical(_pendingBeat, future)) {
        _pendingBeat = null;
      }
    });
  }

  Future<bool> _beat() async {
    if (_released || _lostOwnership) return false;

    final now = _clock().toUtc();
    // Yerel saatte dahi kendi lease süremizi zaten aştıysak (ör. OS askıya alma),
    // başka bir süreç devralmış olabilir -> sessizce geri çekil, kilidi bozma.
    if (now.difference(_lastHeartbeatAt) > _staleAfter) {
      _markOwnershipLost();
      return false;
    }

    for (var i = 0; i < 3; i++) {
      if (_released || _lostOwnership) return false;
      try {
        if (!await _file.exists()) {
          _markOwnershipLost();
          return false;
        }
        final raw = await _file.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          _markOwnershipLost();
          return false;
        }
        final diskToken = decoded['token'] ?? decoded['owner_id'];
        if (diskToken != _token) {
          _markOwnershipLost();
          return false;
        }

        final updated = BackupOperationLock._encodeLockJson(
          kind: _kind,
          token: _token,
          acquiredAt: _acquiredAt,
          heartbeatAt: now,
        );
        final tmpFile = File('${_file.path}.hb.$_token.tmp');
        try {
          await tmpFile.writeAsString(updated, flush: true);
          // Yazım sırasında kilidin el değiştirip değiştirmediğini tekrar denetle.
          final latestRaw = await _file.readAsString();
          final latestJson = jsonDecode(latestRaw) as Map<String, dynamic>;
          final latestToken = latestJson['token'] ?? latestJson['owner_id'];
          final preRenameNow = _clock().toUtc();
          if (latestToken != _token || preRenameNow.difference(_lastHeartbeatAt) > _staleAfter) {
            await BackupOperationLock._deleteFileQuietly(tmpFile);
            _markOwnershipLost();
            return false;
          }
          await tmpFile.rename(_file.path);
          _lastHeartbeatAt = now;
          _consecutiveBeatErrors = 0;
          return true;
        } catch (e) {
          await BackupOperationLock._deleteFileQuietly(tmpFile);
          rethrow;
        }
      } on FileSystemException catch (e) {
        if (i < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 15));
          continue;
        }
        _consecutiveBeatErrors++;
        stderr.writeln('[BackupLock] Heartbeat dosya erişim uyarısı: ${e.message}');
        if (_clock().toUtc().difference(_lastHeartbeatAt) > _staleAfter ||
            _consecutiveBeatErrors >= 3) {
          _markOwnershipLost();
        }
        return false;
      } on FormatException {
        _markOwnershipLost();
        return false;
      } on TypeError {
        _markOwnershipLost();
        return false;
      }
    }
    return false;
  }

  void _markOwnershipLost() {
    _lostOwnership = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final pending = _pendingBeat;
    if (pending != null) {
      try {
        await pending;
      } catch (e) {
        stderr.writeln('[BackupLock] Kapanış heartbeat bekleme uyarısı: $e');
      }
    }

    await BackupOperationLock._deleteFileQuietly(File('${_file.path}.hb.$_token.tmp'));

    for (var i = 0; i < 3; i++) {
      try {
        if (!await _file.exists()) return;
        final raw = await _file.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final diskToken = json['token'] ?? json['owner_id'];
        if (diskToken != _token) return; // Kilit eskidiği için başkası devralmış.
        await _file.delete();
        return;
      } on FileSystemException catch (e) {
        if (!await _file.exists()) return;
        if (i < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 15));
          continue;
        }
        stderr.writeln('[BackupLock] Kilit bırakılamadı: ${e.message}');
      } on FormatException {
        // Başka bir sürecin yarım yazdığı kilit: dokunulmaz.
        return;
      } on TypeError {
        // Beklenmeyen biçim: başkasına ait sayılır, dokunulmaz.
        return;
      }
    }
  }
}
