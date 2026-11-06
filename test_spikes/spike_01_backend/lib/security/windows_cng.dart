import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'ecdsa_signature_validator.dart';

// Typedefs for Windows ncrypt.dll API
typedef NCryptOpenStorageProviderNative = Int32 Function(
  Pointer<IntPtr> phProvider,
  Pointer<Utf16> pszProviderName,
  Uint32 dwFlags,
);
typedef NCryptOpenStorageProviderDart = int Function(
  Pointer<IntPtr> phProvider,
  Pointer<Utf16> pszProviderName,
  int dwFlags,
);

typedef NCryptCreatePersistedKeyNative = Int32 Function(
  IntPtr hProvider,
  Pointer<IntPtr> phKey,
  Pointer<Utf16> pszAlgId,
  Pointer<Utf16> pszKeyName,
  Uint32 dwLegacyKeySpec,
  Uint32 dwFlags,
);
typedef NCryptCreatePersistedKeyDart = int Function(
  int hProvider,
  Pointer<IntPtr> phKey,
  Pointer<Utf16> pszAlgId,
  Pointer<Utf16> pszKeyName,
  int dwLegacyKeySpec,
  int dwFlags,
);

typedef NCryptFinalizeKeyNative = Int32 Function(
  IntPtr hKey,
  Uint32 dwFlags,
);
typedef NCryptFinalizeKeyDart = int Function(
  int hKey,
  int dwFlags,
);

typedef NCryptExportKeyNative = Int32 Function(
  IntPtr hKey,
  IntPtr hExportKey,
  Pointer<Utf16> pszBlobType,
  Pointer<Void> pParameterList,
  Pointer<Uint8> pbOutput,
  Uint32 cbOutput,
  Pointer<Uint32> pcbResult,
  Uint32 dwFlags,
);
typedef NCryptExportKeyDart = int Function(
  int hKey,
  int hExportKey,
  Pointer<Utf16> pszBlobType,
  Pointer<Void> pParameterList,
  Pointer<Uint8> pbOutput,
  int cbOutput,
  Pointer<Uint32> pcbResult,
  int dwFlags,
);

typedef NCryptSignHashNative = Int32 Function(
  IntPtr hKey,
  Pointer<Void> pPaddingInfo,
  Pointer<Uint8> pbHashValue,
  Uint32 cbHashValue,
  Pointer<Uint8> pbSignature,
  Uint32 cbSignature,
  Pointer<Uint32> pcbResult,
  Uint32 dwFlags,
);
typedef NCryptSignHashDart = int Function(
  int hKey,
  Pointer<Void> pPaddingInfo,
  Pointer<Uint8> pbHashValue,
  int cbHashValue,
  Pointer<Uint8> pbSignature,
  int cbSignature,
  Pointer<Uint32> pcbResult,
  int dwFlags,
);

typedef NCryptFreeObjectNative = Int32 Function(IntPtr hObject);
typedef NCryptFreeObjectDart = int Function(int hObject);

typedef NCryptDeleteKeyNative = Int32 Function(IntPtr hKey, Uint32 dwFlags);
typedef NCryptDeleteKeyDart = int Function(int hKey, int dwFlags);

/// Windows CNG İmzalama ve Sağlayıcı Doğrulama Sonucu
class WindowsCngResult {
  final bool isSuccess;
  final String providerName;
  final bool isHardwareTpm;
  final int rawSignatureLength;
  final Uint8List rawSignatureBytes;
  final Uint8List canonicalDerSignature;
  final Uint8List publicKeyBytes;
  final String? errorMessage;

  WindowsCngResult({
    required this.isSuccess,
    required this.providerName,
    required this.isHardwareTpm,
    required this.rawSignatureLength,
    required this.rawSignatureBytes,
    required this.canonicalDerSignature,
    required this.publicKeyBytes,
    this.errorMessage,
  });
}

/// S4-1: Windows CNG (Key Storage Provider) Doğrulama ve İmza Çıktısı Test Modülü
class WindowsCngSigner {
  static const String msPlatformCryptoProvider = 'Microsoft Platform Crypto Provider';
  static const String msSoftwareKeyStorageProvider = 'Microsoft Software Key Storage Provider';
  static const String bCryptEcdsaP256Alg = 'ECDSA_P256';
  static const String bCryptEccPublicBlob = 'ECCPUBLICBLOB';

  static DynamicLibrary? _ncryptLib;

  static DynamicLibrary get _ncrypt {
    if (_ncryptLib != null) return _ncryptLib!;
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows CNG yalnızca Windows işletim sisteminde desteklenir');
    }
    _ncryptLib = DynamicLibrary.open('ncrypt.dll');
    return _ncryptLib!;
  }

  /// Gerçek Windows KSP üzerinde ECDSA P-256 anahtarı oluşturur, tekil SHA-256 ile özetlenmiş
  /// canonical payload'ı imzalar ve ham çıktı formatı ile DER dönüşümünü test eder.
  static WindowsCngResult testCngSigning({
    required List<int> canonicalPayload,
    bool tryTpmFirst = true,
  }) {
    if (!Platform.isWindows) {
      return WindowsCngResult(
        isSuccess: false,
        providerName: 'None (Non-Windows)',
        isHardwareTpm: false,
        rawSignatureLength: 0,
        rawSignatureBytes: Uint8List(0),
        canonicalDerSignature: Uint8List(0),
        publicKeyBytes: Uint8List(0),
        errorMessage: 'İşletim sistemi Windows değil',
      );
    }

    final openProvider = _ncrypt.lookupFunction<NCryptOpenStorageProviderNative, NCryptOpenStorageProviderDart>(
      'NCryptOpenStorageProvider',
    );
    final createKey = _ncrypt.lookupFunction<NCryptCreatePersistedKeyNative, NCryptCreatePersistedKeyDart>(
      'NCryptCreatePersistedKey',
    );
    final finalizeKey = _ncrypt.lookupFunction<NCryptFinalizeKeyNative, NCryptFinalizeKeyDart>(
      'NCryptFinalizeKey',
    );
    final exportKey = _ncrypt.lookupFunction<NCryptExportKeyNative, NCryptExportKeyDart>(
      'NCryptExportKey',
    );
    final signHash = _ncrypt.lookupFunction<NCryptSignHashNative, NCryptSignHashDart>(
      'NCryptSignHash',
    );
    final freeObject = _ncrypt.lookupFunction<NCryptFreeObjectNative, NCryptFreeObjectDart>(
      'NCryptFreeObject',
    );
    final deleteKey = _ncrypt.lookupFunction<NCryptDeleteKeyNative, NCryptDeleteKeyDart>(
      'NCryptDeleteKey',
    );

    int hProvider = 0;
    int hKey = 0;
    var providerUsed = msSoftwareKeyStorageProvider;
    var isTpm = false;

    final pProvider = calloc<IntPtr>();
    final pKey = calloc<IntPtr>();

    try {
      // 1. Sağlayıcıyı aç (Önce TPM dene, desteklenmiyorsa Software KSP'ye düş)
      var status = -1;
      if (tryTpmFirst) {
        final tpmNamePtr = msPlatformCryptoProvider.toNativeUtf16();
        status = openProvider(pProvider, tpmNamePtr, 0);
        calloc.free(tpmNamePtr);
        if (status == 0) {
          providerUsed = msPlatformCryptoProvider;
          isTpm = true;
          hProvider = pProvider.value;
        }
      }

      if (status != 0) {
        final swNamePtr = msSoftwareKeyStorageProvider.toNativeUtf16();
        status = openProvider(pProvider, swNamePtr, 0);
        calloc.free(swNamePtr);
        if (status != 0) {
          return WindowsCngResult(
            isSuccess: false,
            providerName: 'Failed',
            isHardwareTpm: false,
            rawSignatureLength: 0,
            rawSignatureBytes: Uint8List(0),
            canonicalDerSignature: Uint8List(0),
            publicKeyBytes: Uint8List(0),
            errorMessage: 'NCryptOpenStorageProvider başarısız: 0x${status.toRadixString(16)}',
          );
        }
        providerUsed = msSoftwareKeyStorageProvider;
        isTpm = false;
        hProvider = pProvider.value;
      }

      // 2. ECDSA P-256 Anahtarı Üret (Geçici bellek içi anahtar: pszKeyName = NULL)
      final algPtr = bCryptEcdsaP256Alg.toNativeUtf16();
      status = createKey(hProvider, pKey, algPtr, nullptr, 0, 0);
      calloc.free(algPtr);

      if (status != 0) {
        return WindowsCngResult(
          isSuccess: false,
          providerName: providerUsed,
          isHardwareTpm: isTpm,
          rawSignatureLength: 0,
          rawSignatureBytes: Uint8List(0),
          canonicalDerSignature: Uint8List(0),
          publicKeyBytes: Uint8List(0),
          errorMessage: 'NCryptCreatePersistedKey başarısız: 0x${status.toRadixString(16)}',
        );
      }
      hKey = pKey.value;

      status = finalizeKey(hKey, 0);
      if (status != 0) {
        return WindowsCngResult(
          isSuccess: false,
          providerName: providerUsed,
          isHardwareTpm: isTpm,
          rawSignatureLength: 0,
          rawSignatureBytes: Uint8List(0),
          canonicalDerSignature: Uint8List(0),
          publicKeyBytes: Uint8List(0),
          errorMessage: 'NCryptFinalizeKey başarısız: 0x${status.toRadixString(16)}',
        );
      }

      // 3. Açık Anahtarı Dışa Aktar (BCRYPT_ECCPUBLIC_BLOB)
      final blobTypePtr = bCryptEccPublicBlob.toNativeUtf16();
      final pcbResult = calloc<Uint32>();

      // Önce boyut al
      status = exportKey(hKey, 0, blobTypePtr, nullptr, nullptr, 0, pcbResult, 0);
      if (status != 0) {
        calloc.free(blobTypePtr);
        calloc.free(pcbResult);
        return WindowsCngResult(
          isSuccess: false,
          providerName: providerUsed,
          isHardwareTpm: isTpm,
          rawSignatureLength: 0,
          rawSignatureBytes: Uint8List(0),
          canonicalDerSignature: Uint8List(0),
          publicKeyBytes: Uint8List(0),
          errorMessage: 'NCryptExportKey (size query) başarısız: 0x${status.toRadixString(16)}',
        );
      }

      final blobSize = pcbResult.value;
      final pBlob = calloc<Uint8>(blobSize);
      status = exportKey(hKey, 0, blobTypePtr, nullptr, pBlob, blobSize, pcbResult, 0);
      calloc.free(blobTypePtr);

      if (status != 0 || blobSize < 72) {
        calloc.free(pBlob);
        calloc.free(pcbResult);
        return WindowsCngResult(
          isSuccess: false,
          providerName: providerUsed,
          isHardwareTpm: isTpm,
          rawSignatureLength: 0,
          rawSignatureBytes: Uint8List(0),
          canonicalDerSignature: Uint8List(0),
          publicKeyBytes: Uint8List(0),
          errorMessage: 'NCryptExportKey başarısız: 0x${status.toRadixString(16)}',
        );
      }

      // BCRYPT_ECCKEY_BLOB: dwMagic (4) + cbKey (4) + X (32) + Y (32) = 72 bayt
      // Açık anahtar uncompressed formatı: 0x04 || X || Y (65 bayt)
      final xBytes = pBlob.asTypedList(blobSize).sublist(8, 40);
      final yBytes = pBlob.asTypedList(blobSize).sublist(40, 72);
      final rawPublicKey = Uint8List.fromList([0x04, ...xBytes, ...yBytes]);
      calloc.free(pBlob);

      // 4. Tekil SHA-256 Hashing: canonicalPayload yalnızca BİR KEZ hash edilir!
      final digestBytes = sha256.convert(canonicalPayload).bytes;
      final pHash = calloc<Uint8>(32);
      pHash.asTypedList(32).setAll(0, digestBytes);

      // 5. NCryptSignHash ile İmzala
      // Önce imza boyutu al
      status = signHash(hKey, nullptr, pHash, 32, nullptr, 0, pcbResult, 0);
      if (status != 0) {
        calloc.free(pHash);
        calloc.free(pcbResult);
        return WindowsCngResult(
          isSuccess: false,
          providerName: providerUsed,
          isHardwareTpm: isTpm,
          rawSignatureLength: 0,
          rawSignatureBytes: Uint8List(0),
          canonicalDerSignature: Uint8List(0),
          publicKeyBytes: rawPublicKey,
          errorMessage: 'NCryptSignHash (size query) başarısız: 0x${status.toRadixString(16)}',
        );
      }

      final sigSize = pcbResult.value;
      final pSig = calloc<Uint8>(sigSize);
      status = signHash(hKey, nullptr, pHash, 32, pSig, sigSize, pcbResult, 0);
      calloc.free(pHash);

      if (status != 0) {
        calloc.free(pSig);
        calloc.free(pcbResult);
        return WindowsCngResult(
          isSuccess: false,
          providerName: providerUsed,
          isHardwareTpm: isTpm,
          rawSignatureLength: 0,
          rawSignatureBytes: Uint8List(0),
          canonicalDerSignature: Uint8List(0),
          publicKeyBytes: rawPublicKey,
          errorMessage: 'NCryptSignHash imzalama başarısız: 0x${status.toRadixString(16)}',
        );
      }

      final rawSignature = Uint8List.fromList(pSig.asTypedList(sigSize));
      calloc.free(pSig);
      calloc.free(pcbResult);

      // 6. Format Kabul Kriteri: rawSignatureLength == 64 (IEEE P1363: r || s)
      // Normalizasyon: Low-S ve ASN.1 DER dönüşümü
      Uint8List canonicalDer;
      try {
        if (rawSignature.length == 64) {
          canonicalDer = EcdsaSignatureValidator.p1363ToDer(rawSignature, normalizeHighS: true);
        } else if (rawSignature[0] == 0x30) {
          canonicalDer = rawSignature;
        } else {
          throw FormatException('Bilinmeyen imza boyutu: ${rawSignature.length}');
        }
      } catch (e) {
        return WindowsCngResult(
          isSuccess: false,
          providerName: providerUsed,
          isHardwareTpm: isTpm,
          rawSignatureLength: rawSignature.length,
          rawSignatureBytes: rawSignature,
          canonicalDerSignature: Uint8List(0),
          publicKeyBytes: rawPublicKey,
          errorMessage: 'DER/Low-S normalizasyon hatası: $e',
        );
      }

      return WindowsCngResult(
        isSuccess: true,
        providerName: providerUsed,
        isHardwareTpm: isTpm,
        rawSignatureLength: rawSignature.length,
        rawSignatureBytes: rawSignature,
        canonicalDerSignature: canonicalDer,
        publicKeyBytes: rawPublicKey,
      );
    } finally {
      if (hKey != 0) {
        deleteKey(hKey, 0);
        freeObject(hKey);
      }
      if (hProvider != 0) {
        freeObject(hProvider);
      }
      calloc.free(pProvider);
      calloc.free(pKey);
    }
  }
}
