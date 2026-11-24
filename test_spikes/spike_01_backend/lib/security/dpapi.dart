import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

final class DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef CryptProtectDataNative = Int32 Function(
  Pointer<DataBlob> pDataIn,
  Pointer<Void> szDataDescr,
  Pointer<DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<DataBlob> pDataOut,
);

typedef CryptProtectDataDart = int Function(
  Pointer<DataBlob> pDataIn,
  Pointer<Void> szDataDescr,
  Pointer<DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<DataBlob> pDataOut,
);

typedef CryptUnprotectDataNative = Int32 Function(
  Pointer<DataBlob> pDataIn,
  Pointer<Void> ppszDataDescr,
  Pointer<DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<DataBlob> pDataOut,
);

typedef CryptUnprotectDataDart = int Function(
  Pointer<DataBlob> pDataIn,
  Pointer<Void> ppszDataDescr,
  Pointer<DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<DataBlob> pDataOut,
);

typedef LocalAllocNative = Pointer<Void> Function(Uint32 uFlags, IntPtr uBytes);
typedef LocalAllocDart = Pointer<Void> Function(int uFlags, int uBytes);

typedef LocalFreeNative = Pointer<Void> Function(Pointer<Void> hMem);
typedef LocalFreeDart = Pointer<Void> Function(Pointer<Void> hMem);

/// Windows Data Protection API (DPAPI) sarmalayıcısı.
/// LocalMachine kapsamı ile makineye bağlı zarf şifrelemesi (envelope encryption) sağlar.
class WindowsDpapi {
  static const int cryptProtectLocalMachine = 0x4;
  static const int cryptProtectUiForbidden = 0x1;

  static const int lmemFixed = 0x0000;
  static const int lmemZeroinit = 0x0040;
  static const int allocFlags = lmemFixed | lmemZeroinit;

  static DynamicLibrary? _crypt32;
  static DynamicLibrary? _kernel32;
  static CryptProtectDataDart? _protect;
  static CryptUnprotectDataDart? _unprotect;
  static LocalAllocDart? _localAlloc;
  static LocalFreeDart? _localFree;

  static void _init() {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows DPAPI yalnızca Windows işletim sisteminde desteklenir.');
    }
    if (_crypt32 != null) return;

    _crypt32 = DynamicLibrary.open('Crypt32.dll');
    _kernel32 = DynamicLibrary.open('kernel32.dll');

    _protect = _crypt32!.lookupFunction<CryptProtectDataNative, CryptProtectDataDart>('CryptProtectData');
    _unprotect = _crypt32!.lookupFunction<CryptUnprotectDataNative, CryptUnprotectDataDart>('CryptUnprotectData');
    _localAlloc = _kernel32!.lookupFunction<LocalAllocNative, LocalAllocDart>('LocalAlloc');
    _localFree = _kernel32!.lookupFunction<LocalFreeNative, LocalFreeDart>('LocalFree');
  }

  /// Verilen byte dizisini DPAPI LocalMachine kapsamı ile şifreler.
  /// İsteğe bağlı [entropy] verildiğinde `pOptionalEntropy` bağlaması uygulanır (`OV-01`).
  static Uint8List protect(List<int> plainBytes, {List<int>? entropy}) {
    _init();

    final inBlob = _localAlloc!(allocFlags, sizeOf<DataBlob>()).cast<DataBlob>();
    final inData = _localAlloc!(allocFlags, plainBytes.length).cast<Uint8>();
    for (var i = 0; i < plainBytes.length; i++) {
      inData[i] = plainBytes[i];
    }
    inBlob.ref.cbData = plainBytes.length;
    inBlob.ref.pbData = inData;

    Pointer<DataBlob> entropyBlob = nullptr;
    Pointer<Uint8> entropyData = nullptr;
    if (entropy != null && entropy.isNotEmpty) {
      entropyBlob = _localAlloc!(allocFlags, sizeOf<DataBlob>()).cast<DataBlob>();
      entropyData = _localAlloc!(allocFlags, entropy.length).cast<Uint8>();
      for (var i = 0; i < entropy.length; i++) {
        entropyData[i] = entropy[i];
      }
      entropyBlob.ref.cbData = entropy.length;
      entropyBlob.ref.pbData = entropyData;
    }

    final outBlob = _localAlloc!(allocFlags, sizeOf<DataBlob>()).cast<DataBlob>();

    try {
      final success = _protect!(
        inBlob,
        nullptr,
        entropyBlob,
        nullptr,
        nullptr,
        cryptProtectLocalMachine | cryptProtectUiForbidden,
        outBlob,
      );

      if (success == 0) {
        throw StateError('DPAPI CryptProtectData başarısız oldu.');
      }

      final result = outBlob.ref.pbData.asTypedList(outBlob.ref.cbData).sublist(0);
      return Uint8List.fromList(result);
    } finally {
      _localFree!(inData.cast<Void>());
      _localFree!(inBlob.cast<Void>());
      if (entropyData != nullptr) {
        _localFree!(entropyData.cast<Void>());
      }
      if (entropyBlob != nullptr) {
        _localFree!(entropyBlob.cast<Void>());
      }
      if (outBlob.ref.pbData != nullptr) {
        _localFree!(outBlob.ref.pbData.cast<Void>());
      }
      _localFree!(outBlob.cast<Void>());
    }
  }

  /// DPAPI ile şifrelenmiş byte dizisini çözer.
  /// Şifreleme sırasında [entropy] kullanıldıysa aynı [entropy] verilmelidir.
  static Uint8List unprotect(List<int> cipherBytes, {List<int>? entropy}) {
    _init();

    final cipherBlob = _localAlloc!(allocFlags, sizeOf<DataBlob>()).cast<DataBlob>();
    final cipherData = _localAlloc!(allocFlags, cipherBytes.length).cast<Uint8>();
    for (var i = 0; i < cipherBytes.length; i++) {
      cipherData[i] = cipherBytes[i];
    }
    cipherBlob.ref.cbData = cipherBytes.length;
    cipherBlob.ref.pbData = cipherData;

    Pointer<DataBlob> entropyBlob = nullptr;
    Pointer<Uint8> entropyData = nullptr;
    if (entropy != null && entropy.isNotEmpty) {
      entropyBlob = _localAlloc!(allocFlags, sizeOf<DataBlob>()).cast<DataBlob>();
      entropyData = _localAlloc!(allocFlags, entropy.length).cast<Uint8>();
      for (var i = 0; i < entropy.length; i++) {
        entropyData[i] = entropy[i];
      }
      entropyBlob.ref.cbData = entropy.length;
      entropyBlob.ref.pbData = entropyData;
    }

    final plainBlob = _localAlloc!(allocFlags, sizeOf<DataBlob>()).cast<DataBlob>();

    try {
      final success = _unprotect!(
        cipherBlob,
        nullptr,
        entropyBlob,
        nullptr,
        nullptr,
        cryptProtectUiForbidden,
        plainBlob,
      );

      if (success == 0) {
        throw StateError('DPAPI CryptUnprotectData başarısız oldu. Veri bozuk, entropy yanlış veya yetki yetersiz.');
      }

      final result = plainBlob.ref.pbData.asTypedList(plainBlob.ref.cbData).sublist(0);
      return Uint8List.fromList(result);
    } finally {
      _localFree!(cipherData.cast<Void>());
      _localFree!(cipherBlob.cast<Void>());
      if (entropyData != nullptr) {
        _localFree!(entropyData.cast<Void>());
      }
      if (entropyBlob != nullptr) {
        _localFree!(entropyBlob.cast<Void>());
      }
      if (plainBlob.ref.pbData != nullptr) {
        _localFree!(plainBlob.ref.pbData.cast<Void>());
      }
      _localFree!(plainBlob.cast<Void>());
    }
  }

  /// String şifreleme yardımcısı
  static Uint8List protectString(String plainText, {List<int>? entropy}) =>
      protect(utf8.encode(plainText), entropy: entropy);

  /// String çözme yardımcısı
  static String unprotectString(List<int> cipherBytes, {List<int>? entropy}) =>
      utf8.decode(unprotect(cipherBytes, entropy: entropy));
}

