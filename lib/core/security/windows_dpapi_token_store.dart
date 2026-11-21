import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'secure_token_store.dart';

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptProtectDataNative = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Void> szDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _CryptProtectDataDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Void> szDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _CryptUnprotectDataNative = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Void> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _CryptUnprotectDataDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Void> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _LocalAllocNative = Pointer<Void> Function(Uint32 uFlags, IntPtr uBytes);
typedef _LocalAllocDart = Pointer<Void> Function(int uFlags, int uBytes);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> hMem);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> hMem);

/// Windows Data Protection API (DPAPI - CurrentUser kapsamı) ile şifreli istemci deposu.
class ClientWindowsDpapi {
  static const int _cryptProtectUiForbidden = 0x1;
  static const int _lmemAllocFlags = 0x0040;

  static DynamicLibrary? _crypt32;
  static DynamicLibrary? _kernel32;
  static _CryptProtectDataDart? _protect;
  static _CryptUnprotectDataDart? _unprotect;
  static _LocalAllocDart? _localAlloc;
  static _LocalFreeDart? _localFree;

  static void _ensureLoaded() {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows DPAPI yalnızca Windows üzerinde desteklenir.');
    }
    if (_crypt32 != null) return;
    _crypt32 = DynamicLibrary.open('Crypt32.dll');
    _kernel32 = DynamicLibrary.open('kernel32.dll');
    _protect = _crypt32!.lookupFunction<_CryptProtectDataNative, _CryptProtectDataDart>(
      'CryptProtectData',
    );
    _unprotect =
        _crypt32!.lookupFunction<_CryptUnprotectDataNative, _CryptUnprotectDataDart>(
      'CryptUnprotectData',
    );
    _localAlloc = _kernel32!.lookupFunction<_LocalAllocNative, _LocalAllocDart>(
      'LocalAlloc',
    );
    _localFree = _kernel32!.lookupFunction<_LocalFreeNative, _LocalFreeDart>(
      'LocalFree',
    );
  }

  static Uint8List protectBytes(List<int> plainBytes) {
    _ensureLoaded();
    final allocLen = plainBytes.isEmpty ? 1 : plainBytes.length;
    final inBlob = _localAlloc!(_lmemAllocFlags, sizeOf<_DataBlob>()).cast<_DataBlob>();
    final inData = _localAlloc!(_lmemAllocFlags, allocLen).cast<Uint8>();
    for (var i = 0; i < plainBytes.length; i++) {
      inData[i] = plainBytes[i];
    }
    inBlob.ref.cbData = plainBytes.length;
    inBlob.ref.pbData = inData;

    final outBlob = _localAlloc!(_lmemAllocFlags, sizeOf<_DataBlob>()).cast<_DataBlob>();
    try {
      final ok = _protect!(
        inBlob,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        outBlob,
      );
      if (ok == 0) {
        throw StateError('Windows DPAPI CryptProtectData başarısız.');
      }
      return Uint8List.fromList(
        outBlob.ref.pbData.asTypedList(outBlob.ref.cbData),
      );
    } finally {
      _localFree!(inData.cast<Void>());
      _localFree!(inBlob.cast<Void>());
      if (outBlob.ref.pbData != nullptr) {
        _localFree!(outBlob.ref.pbData.cast<Void>());
      }
      _localFree!(outBlob.cast<Void>());
    }
  }

  static Uint8List unprotectBytes(List<int> cipherBytes) {
    _ensureLoaded();
    if (cipherBytes.isEmpty) {
      throw StateError('Boş DPAPI şifreli veri çözülemez.');
    }
    final inBlob = _localAlloc!(_lmemAllocFlags, sizeOf<_DataBlob>()).cast<_DataBlob>();
    final inData = _localAlloc!(_lmemAllocFlags, cipherBytes.length).cast<Uint8>();
    for (var i = 0; i < cipherBytes.length; i++) {
      inData[i] = cipherBytes[i];
    }
    inBlob.ref.cbData = cipherBytes.length;
    inBlob.ref.pbData = inData;

    final outBlob = _localAlloc!(_lmemAllocFlags, sizeOf<_DataBlob>()).cast<_DataBlob>();
    try {
      final ok = _unprotect!(
        inBlob,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        outBlob,
      );
      if (ok == 0) {
        throw StateError('Windows DPAPI CryptUnprotectData başarısız.');
      }
      return Uint8List.fromList(
        outBlob.ref.pbData.asTypedList(outBlob.ref.cbData),
      );
    } finally {
      _localFree!(inData.cast<Void>());
      _localFree!(inBlob.cast<Void>());
      if (outBlob.ref.pbData != nullptr) {
        _localFree!(outBlob.ref.pbData.cast<Void>());
      }
      _localFree!(outBlob.cast<Void>());
    }
  }
}

/// B-3 Windows İstemci Güvenli Token Deposu (CurrentUser DPAPI zarf şifrelemesi).
class WindowsDpapiTokenStore implements SecureTokenStore {
  static const String defaultFileName = 'secure_tokens.dpapi.json';

  final File storageFile;

  WindowsDpapiTokenStore({required this.storageFile});

  factory WindowsDpapiTokenStore.inDirectory(Directory dataDir) {
    return WindowsDpapiTokenStore(
      storageFile: File(p.join(dataDir.path, defaultFileName)),
    );
  }

  @override
  String get backendLabel => 'Windows DPAPI (CurrentUser)';

  String _tokenKey(String deviceId) => 'device_token::$deviceId';

  Future<Map<String, String>> _readAllEncrypted() async {
    if (!await storageFile.exists()) {
      return <String, String>{};
    }
    // Fail-closed: Bozuk/okunamayan depo boş kabul EDİLMEZ; aksi halde sonraki yazma
    // mevcut tüm sırları (cihaz token'ı, sabitlenmiş sertifika vb.) sessizce silerdi.
    final String raw;
    try {
      raw = await storageFile.readAsString();
    } on FileSystemException catch (e) {
      throw SecureStorageException('Güvenli token deposu okunamadı: ${e.osError?.message ?? e.message}');
    }
    if (raw.trim().isEmpty) return <String, String>{};
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const SecureStorageException('Güvenli token deposu bozuk (geçersiz JSON).');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const SecureStorageException('Güvenli token deposu beklenmeyen biçimde.');
    }
    return decoded.map((k, v) => MapEntry(k, v.toString()));
  }

  Future<void> _writeAllEncrypted(Map<String, String> map) async {
    if (!storageFile.parent.existsSync()) {
      storageFile.parent.createSync(recursive: true);
    }
    final tmpFile = File('${storageFile.path}.tmp');
    await tmpFile.writeAsString(jsonEncode(map), flush: true);
    if (await storageFile.exists()) {
      await storageFile.delete();
    }
    await tmpFile.rename(storageFile.path);
  }

  @override
  Future<void> saveDeviceToken(String deviceId, String token) =>
      saveSecret(_tokenKey(deviceId), token);

  @override
  Future<String?> readDeviceToken(String deviceId) =>
      readSecret(_tokenKey(deviceId));

  @override
  Future<void> deleteDeviceToken(String deviceId) =>
      deleteSecret(_tokenKey(deviceId));

  @override
  Future<void> saveSecret(String key, String value) async {
    final map = await _readAllEncrypted();
    final protected = ClientWindowsDpapi.protectBytes(utf8.encode(value));
    map[key] = base64Encode(protected);
    await _writeAllEncrypted(map);
  }

  @override
  Future<String?> readSecret(String key) async {
    final map = await _readAllEncrypted();
    final encoded = map[key];
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final plainBytes = ClientWindowsDpapi.unprotectBytes(base64Decode(encoded));
      return utf8.decode(plainBytes);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteSecret(String key) async {
    final map = await _readAllEncrypted();
    if (!map.containsKey(key)) return;
    map.remove(key);
    await _writeAllEncrypted(map);
  }
}
