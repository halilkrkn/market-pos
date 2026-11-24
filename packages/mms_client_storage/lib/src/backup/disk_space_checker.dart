import 'dart:ffi';
import 'dart:io';

typedef _GetDiskFreeSpaceExWNative = Int32 Function(
  Pointer<Uint16> lpDirectoryName,
  Pointer<Uint64> lpFreeBytesAvailableToCaller,
  Pointer<Uint64> lpTotalNumberOfBytes,
  Pointer<Uint64> lpTotalNumberOfFreeBytes,
);
typedef _GetDiskFreeSpaceExWDart = int Function(
  Pointer<Uint16> lpDirectoryName,
  Pointer<Uint64> lpFreeBytesAvailableToCaller,
  Pointer<Uint64> lpTotalNumberOfBytes,
  Pointer<Uint64> lpTotalNumberOfFreeBytes,
);

typedef _LocalAllocNative = Pointer<Void> Function(Uint32 uFlags, IntPtr uBytes);
typedef _LocalAllocDart = Pointer<Void> Function(int uFlags, int uBytes);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> hMem);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> hMem);

class DiskSpaceCheckResult {
  final bool ok;
  final int requiredBytes;
  final int? availableBytes;
  final String? reason;

  const DiskSpaceCheckResult({
    required this.ok,
    required this.requiredBytes,
    this.availableBytes,
    this.reason,
  });
}

/// Faz B-1: Snapshot + şifreleme öncesi disk alanı kontrolü.
/// Formül: `requiredBytes = ceil(2.5 * (db + wal)) + 64 MiB`.
class DiskSpaceChecker {
  static const int minBufferBytes = 64 * 1024 * 1024;
  static const double safetyMultiplier = 2.5;

  final Future<int?> Function(String path)? freeBytesProbe;

  const DiskSpaceChecker({this.freeBytesProbe});

  static int computeRequiredBytes({
    required int dbBytes,
    required int walBytes,
  }) {
    final totalDb = (dbBytes < 0 ? 0 : dbBytes) + (walBytes < 0 ? 0 : walBytes);
    return (totalDb * safetyMultiplier).ceil() + minBufferBytes;
  }

  Future<DiskSpaceCheckResult> checkForDatabase({
    required File databaseFile,
    required Directory targetDir,
  }) async {
    final dbBytes = await databaseFile.exists() ? await databaseFile.length() : 0;
    final walFile = File('${databaseFile.path}-wal');
    final walBytes = await walFile.exists() ? await walFile.length() : 0;
    final requiredBytes = computeRequiredBytes(dbBytes: dbBytes, walBytes: walBytes);

    final available = await queryAvailableBytes(targetDir.path);
    if (available == null) {
      return DiskSpaceCheckResult(
        ok: true,
        requiredBytes: requiredBytes,
        availableBytes: null,
        reason: 'Disk boş alan ölçümü bu platformda desteklenmedi; devam edildi.',
      );
    }

    if (available < requiredBytes) {
      final availMb = (available / (1024 * 1024)).toStringAsFixed(1);
      final reqMb = (requiredBytes / (1024 * 1024)).toStringAsFixed(1);
      return DiskSpaceCheckResult(
        ok: false,
        requiredBytes: requiredBytes,
        availableBytes: available,
        reason:
            'Yedekleme için yeterli disk alanı yok (gereken: $reqMb MB, mevcut: $availMb MB).',
      );
    }

    return DiskSpaceCheckResult(
      ok: true,
      requiredBytes: requiredBytes,
      availableBytes: available,
    );
  }

  Future<int?> queryAvailableBytes(String directoryPath) async {
    if (freeBytesProbe != null) {
      return freeBytesProbe!(directoryPath);
    }
    if (Platform.isWindows) {
      var probeDir = Directory(directoryPath).absolute;
      while (!await probeDir.exists()) {
        final parent = probeDir.parent;
        if (parent.path == probeDir.path) break;
        probeDir = parent;
      }
      return _queryWindowsFreeBytes(probeDir.path);
    }
    return null;
  }

  static DynamicLibrary? _kernel32;
  static _GetDiskFreeSpaceExWDart? _getDiskFreeSpaceExW;
  static _LocalAllocDart? _localAlloc;
  static _LocalFreeDart? _localFree;

  static int? _queryWindowsFreeBytes(String path) {
    _kernel32 ??= DynamicLibrary.open('kernel32.dll');
    _getDiskFreeSpaceExW ??= _kernel32!
        .lookupFunction<_GetDiskFreeSpaceExWNative, _GetDiskFreeSpaceExWDart>(
            'GetDiskFreeSpaceExW');
    _localAlloc ??=
        _kernel32!.lookupFunction<_LocalAllocNative, _LocalAllocDart>('LocalAlloc');
    _localFree ??=
        _kernel32!.lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');

    final normalized = path.endsWith('\\') ? path : '$path\\';
    final units = normalized.codeUnits;
    const allocFlags = 0x0040; // LMEM_FIXED | LMEM_ZEROINIT
    final pathPtr = _localAlloc!(allocFlags, (units.length + 1) * 2).cast<Uint16>();
    final freeAvailPtr = _localAlloc!(allocFlags, sizeOf<Uint64>()).cast<Uint64>();
    final totalPtr = _localAlloc!(allocFlags, sizeOf<Uint64>()).cast<Uint64>();
    final totalFreePtr = _localAlloc!(allocFlags, sizeOf<Uint64>()).cast<Uint64>();

    try {
      for (var i = 0; i < units.length; i++) {
        pathPtr[i] = units[i];
      }
      pathPtr[units.length] = 0;

      final ok = _getDiskFreeSpaceExW!(
        pathPtr,
        freeAvailPtr,
        totalPtr,
        totalFreePtr,
      );
      if (ok == 0) return null;
      return freeAvailPtr.value;
    } finally {
      _localFree!(pathPtr.cast<Void>());
      _localFree!(freeAvailPtr.cast<Void>());
      _localFree!(totalPtr.cast<Void>());
      _localFree!(totalFreePtr.cast<Void>());
    }
  }
}
