import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'backup_manifest.dart';

class BackupCryptoException implements Exception {
  final String message;
  const BackupCryptoException(this.message);

  @override
  String toString() => 'BackupCryptoException: $message';
}

class DecryptedBackupResult {
  final BackupManifest manifest;
  final Uint8List databaseBytes;

  const DecryptedBackupResult({
    required this.manifest,
    required this.databaseBytes,
  });
}

/// S5A-4: Endüstri standardı AES-256-CBC ve HMAC-SHA256 (Encrypt-then-MAC)
/// ile taşınabilir, güvenli ve platformdan bağımsız yedek şifreleme motoru.
class BackupCryptoService {
  static const List<int> magicHeader = [0x4D, 0x4D, 0x53, 0x42, 0x41, 0x4B, 0x30, 0x31]; // 'MMSBAK01'
  static const int defaultPbkdf2Iterations = 600000; // S5A-4: En az 600.000 iterasyon standardı
  static final Random _secureRandom = Random.secure();

  /// Rastgele n baytlık kriptografik tuz veya IV üretir
  static Uint8List generateRandomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytes;
  }

  /// Sabit zamanlı karşılaştırma (Timing Attack Koruması)
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// PBKDF2-HMAC-SHA256: Parola ve tuzdan 64 bayt (32 bayt AES anahtarı + 32 bayt HMAC anahtarı) türetir.
  static DerivedKeys deriveKeys({
    required String password,
    required Uint8List salt,
    int iterations = defaultPbkdf2Iterations,
  }) {
    final passwordBytes = utf8.encode(password);
    final keyBytes = _pbkdf2(
      password: passwordBytes,
      salt: salt,
      iterations: iterations,
      keyLength: 64,
    );

    final encKey = Uint8List.sublistView(keyBytes, 0, 32);
    final hmacKey = Uint8List.sublistView(keyBytes, 32, 64);
    return DerivedKeys(encryptionKey: encKey, hmacKey: hmacKey);
  }

  static Uint8List _pbkdf2({
    required List<int> password,
    required Uint8List salt,
    required int iterations,
    required int keyLength,
  }) {
    final hmac = Hmac(sha256, password);
    final numBlocks = (keyLength + 31) ~/ 32;
    final result = BytesBuilder(copy: false);

    for (var blockIndex = 1; blockIndex <= numBlocks; blockIndex++) {
      // U_1 = PRF(P, S || INT_32_BE(blockIndex))
      final uBuilder = BytesBuilder(copy: false);
      uBuilder.add(salt);
      uBuilder.add([
        (blockIndex >> 24) & 0xff,
        (blockIndex >> 16) & 0xff,
        (blockIndex >> 8) & 0xff,
        blockIndex & 0xff,
      ]);

      var u = Uint8List.fromList(hmac.convert(uBuilder.toBytes()).bytes);
      final t = Uint8List.fromList(u);

      for (var iter = 1; iter < iterations; iter++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var k = 0; k < 32; k++) {
          t[k] ^= u[k];
        }
      }
      result.add(t);
    }

    return Uint8List.sublistView(result.toBytes(), 0, keyLength);
  }

  /// Veritabanı dosyasını şifreler, üstveriyi ekler ve doğrulanabilir .mmsbak ikili paketini üretir
  static Uint8List encryptPackage({
    required Uint8List databaseBytes,
    required String password,
    required BackupManifest manifest,
    Uint8List? customSalt,
    Uint8List? customIv,
  }) {
    final salt = customSalt ?? generateRandomBytes(16);
    final iv = customIv ?? generateRandomBytes(16);

    final derived = deriveKeys(
      password: password,
      salt: salt,
      iterations: manifest.kdfIterations,
    );

    // 1. AES-256-CBC ile veritabanını şifrele
    final ciphertext = Aes256Cbc.encrypt(
      plaintext: databaseBytes,
      key: derived.encryptionKey,
      iv: iv,
    );

    // 2. Manifest'i güncel şifrelenmiş boyutla hazırla
    final finalManifest = manifest.copyWith(
      encryptedSizeBytes: ciphertext.length,
      unencryptedSizeBytes: databaseBytes.length,
    );

    final manifestBytes = utf8.encode(finalManifest.toJsonString());
    final manifestLen = manifestBytes.length;

    // 3. İkili paket yapısını birleştir:
    // [Header (8)] + [ManifestLen (4 BE)] + [Manifest (N)] + [Salt (16)] + [IV (16)] + [Ciphertext (C)]
    final packageBuilder = BytesBuilder(copy: false);
    packageBuilder.add(magicHeader);
    packageBuilder.add([
      (manifestLen >> 24) & 0xff,
      (manifestLen >> 16) & 0xff,
      (manifestLen >> 8) & 0xff,
      manifestLen & 0xff,
    ]);
    packageBuilder.add(manifestBytes);
    packageBuilder.add(salt);
    packageBuilder.add(iv);
    packageBuilder.add(ciphertext);

    final payloadToSign = packageBuilder.toBytes();

    // 4. Encrypt-then-MAC: Tüm paketin üzerine HMAC-SHA256 uygula
    final hmac = Hmac(sha256, derived.hmacKey);
    final tag = hmac.convert(payloadToSign).bytes;

    // [Payload] + [HMAC Tag (32)]
    final finalPackage = BytesBuilder(copy: false);
    finalPackage.add(payloadToSign);
    finalPackage.add(tag);

    return finalPackage.toBytes();
  }

  /// Şifreli paketin bütünlüğünü ve şifresini doğrular; ham veritabanı baytlarını ve manifesti döner
  static DecryptedBackupResult verifyAndDecryptPackage({
    required Uint8List packageBytes,
    required String password,
  }) {
    // Minimum boyut kontrolü: Header(8) + Len(4) + MinManifest(20) + Salt(16) + IV(16) + MinCipher(16) + Tag(32) = 112
    if (packageBytes.length < 112) {
      throw const BackupCryptoException('Yedek paketi hasarlı veya eksik (Minimum boyut sınırının altında).');
    }

    // 1. Magic Header kontrolü
    for (var i = 0; i < 8; i++) {
      if (packageBytes[i] != magicHeader[i]) {
        throw const BackupCryptoException('Geçersiz yedek formatı (MMSBAK01 başlığı bulunamadı).');
      }
    }

    // 2. Manifest uzunluğu ve manifest oku
    final manifestLen = (packageBytes[8] << 24) |
        (packageBytes[9] << 16) |
        (packageBytes[10] << 8) |
        packageBytes[11];

    if (manifestLen <= 0 || 12 + manifestLen + 16 + 16 + 16 + 32 > packageBytes.length) {
      throw const BackupCryptoException('Yedek paketi manifest başlığı bozuk.');
    }

    final manifestBytes = packageBytes.sublist(12, 12 + manifestLen);
    BackupManifest manifest;
    try {
      final manifestJson = utf8.decode(manifestBytes);
      manifest = BackupManifest.fromJsonString(manifestJson);
    } catch (e) {
      throw BackupCryptoException('Yedek manifesti ayrıştırılamadı: $e');
    }

    final saltOffset = 12 + manifestLen;
    final ivOffset = saltOffset + 16;
    final ciphertextOffset = ivOffset + 16;
    final tagOffset = packageBytes.length - 32;

    if (ciphertextOffset > tagOffset) {
      throw const BackupCryptoException('Yedek paketinde şifreli veri gövdesi eksik.');
    }

    final salt = Uint8List.sublistView(packageBytes, saltOffset, ivOffset);
    final iv = Uint8List.sublistView(packageBytes, ivOffset, ciphertextOffset);
    final ciphertext = Uint8List.sublistView(packageBytes, ciphertextOffset, tagOffset);
    final expectedTag = Uint8List.sublistView(packageBytes, tagOffset, packageBytes.length);

    // 3. Anahtar türetme (Manifestteki güvenli iterasyon sayısı ile)
    final derived = deriveKeys(
      password: password,
      salt: salt,
      iterations: manifest.kdfIterations,
    );

    // 4. Encrypt-then-MAC Bütünlük ve Parola Doğrulaması
    final payloadSigned = Uint8List.sublistView(packageBytes, 0, tagOffset);
    final hmac = Hmac(sha256, derived.hmacKey);
    final computedTag = hmac.convert(payloadSigned).bytes;

    if (!constantTimeEquals(computedTag, expectedTag)) {
      throw const BackupCryptoException('Yedek paketi bütünlük doğrulaması (HMAC) başarısız oldu veya şifre yanlış.');
    }

    // 5. AES-256-CBC ile şifre çözme
    Uint8List decryptedDb;
    try {
      decryptedDb = Aes256Cbc.decrypt(
        ciphertext: ciphertext,
        key: derived.encryptionKey,
        iv: iv,
      );
    } catch (e) {
      throw BackupCryptoException('Şifre çözme hatası (AES-CBC): $e');
    }

    // 6. SHA-256 Checksum Kontrolü
    final computedChecksum = sha256.convert(decryptedDb).toString().toLowerCase();
    if (computedChecksum != manifest.checksum.toLowerCase()) {
      throw BackupCryptoException(
        'Çözülen veritabanı sağlama toplamı (checksum) manifest ile uyuşmuyor. Beklenen: ${manifest.checksum}, Hesaplanan: $computedChecksum',
      );
    }

    return DecryptedBackupResult(manifest: manifest, databaseBytes: decryptedDb);
  }

  /// Şifreyi çözmeden yalnızca manifesti güvenle okur (Depolama listelemeleri ve meta incelemeleri için)
  static BackupManifest extractManifestWithoutDecryption(Uint8List packageBytes) {
    if (packageBytes.length < 32) {
      throw const BackupCryptoException('Yedek paketi çok küçük.');
    }

    for (var i = 0; i < 8; i++) {
      if (packageBytes[i] != magicHeader[i]) {
        throw const BackupCryptoException('Geçersiz yedek başlığı.');
      }
    }

    final manifestLen = (packageBytes[8] << 24) |
        (packageBytes[9] << 16) |
        (packageBytes[10] << 8) |
        packageBytes[11];

    if (manifestLen <= 0 || 12 + manifestLen > packageBytes.length) {
      throw const BackupCryptoException('Manifest boyutu geçersiz.');
    }

    final manifestBytes = packageBytes.sublist(12, 12 + manifestLen);
    final manifestJson = utf8.decode(manifestBytes);
    return BackupManifest.fromJsonString(manifestJson);
  }
}

class DerivedKeys {
  final Uint8List encryptionKey; // 32 bytes
  final Uint8List hmacKey; // 32 bytes

  const DerivedKeys({
    required this.encryptionKey,
    required this.hmacKey,
  });
}

/// Standart FIPS 197 AES-256 CBC Modu ve PKCS#7 Dolgu Uygulaması
class Aes256Cbc {
  static Uint8List encrypt({
    required Uint8List plaintext,
    required Uint8List key,
    required Uint8List iv,
  }) {
    if (key.length != 32) throw ArgumentError('AES-256 anahtarı tam 32 bayt olmalıdır.');
    if (iv.length != 16) throw ArgumentError('AES IV tam 16 bayt olmalıdır.');

    final expandedKey = _expandKey(key);
    final padded = _padPkcs7(plaintext, 16);
    final ciphertext = Uint8List(padded.length);

    var prevBlock = Uint8List.fromList(iv);
    final currentBlock = Uint8List(16);

    for (var offset = 0; offset < padded.length; offset += 16) {
      // CBC: Plaintext ^ PrevCiphertext
      for (var i = 0; i < 16; i++) {
        currentBlock[i] = padded[offset + i] ^ prevBlock[i];
      }

      _encryptBlock(currentBlock, expandedKey);

      for (var i = 0; i < 16; i++) {
        ciphertext[offset + i] = currentBlock[i];
        prevBlock[i] = currentBlock[i];
      }
    }

    return ciphertext;
  }

  static Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List key,
    required Uint8List iv,
  }) {
    if (key.length != 32) throw ArgumentError('AES-256 anahtarı tam 32 bayt olmalıdır.');
    if (iv.length != 16) throw ArgumentError('AES IV tam 16 bayt olmalıdır.');
    if (ciphertext.isEmpty || ciphertext.length % 16 != 0) {
      throw ArgumentError('Şifreli metin boyutu 16 baytın tam katı olmalıdır.');
    }

    final expandedKey = _expandKey(key);
    final plaintext = Uint8List(ciphertext.length);

    var prevBlock = Uint8List.fromList(iv);
    final currentBlock = Uint8List(16);

    for (var offset = 0; offset < ciphertext.length; offset += 16) {
      for (var i = 0; i < 16; i++) {
        currentBlock[i] = ciphertext[offset + i];
      }

      _decryptBlock(currentBlock, expandedKey);

      for (var i = 0; i < 16; i++) {
        plaintext[offset + i] = currentBlock[i] ^ prevBlock[i];
        prevBlock[i] = ciphertext[offset + i];
      }
    }

    return _unpadPkcs7(plaintext);
  }

  static Uint8List _padPkcs7(Uint8List src, int blockSize) {
    final padLen = blockSize - (src.length % blockSize);
    final padded = Uint8List(src.length + padLen);
    padded.setRange(0, src.length, src);
    for (var i = src.length; i < padded.length; i++) {
      padded[i] = padLen;
    }
    return padded;
  }

  static Uint8List _unpadPkcs7(Uint8List src) {
    if (src.isEmpty) throw const FormatException('PKCS7 dolgusu geçersiz: Boş veri.');
    final padLen = src.last;
    if (padLen <= 0 || padLen > 16 || padLen > src.length) {
      throw const FormatException('PKCS7 dolgusu geçersiz: Hatalı dolgu uzunluğu.');
    }
    for (var i = src.length - padLen; i < src.length; i++) {
      if (src[i] != padLen) {
        throw const FormatException('PKCS7 dolgusu geçersiz: Uyuşmayan dolgu baytları.');
      }
    }
    return Uint8List.sublistView(src, 0, src.length - padLen);
  }

  // --- AES FIPS 197 Primitives ---

  static const List<int> _sBox = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
  ];

  static const List<int> _invSBox = [
    0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, 0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb,
    0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87, 0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb,
    0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d, 0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
    0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2, 0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25,
    0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92,
    0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda, 0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
    0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a, 0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06,
    0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02, 0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b,
    0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea, 0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
    0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85, 0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e,
    0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89, 0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b,
    0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20, 0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
    0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31, 0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f,
    0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d, 0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef,
    0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0, 0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
    0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26, 0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d,
  ];

  static const List<int> _rcon = [
    0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36,
  ];

  static Uint32List _expandKey(Uint8List key) {
    // AES-256: Nk = 8, Nr = 14, Toplam round key sayısı = 4 * (14 + 1) = 60 uint32
    final w = Uint32List(60);
    for (var i = 0; i < 8; i++) {
      w[i] = (key[4 * i] << 24) |
          (key[4 * i + 1] << 16) |
          (key[4 * i + 2] << 8) |
          key[4 * i + 3];
    }

    for (var i = 8; i < 60; i++) {
      var temp = w[i - 1];
      if (i % 8 == 0) {
        temp = _subWord(_rotWord(temp)) ^ (_rcon[i ~/ 8] << 24);
      } else if (i % 8 == 4) {
        temp = _subWord(temp);
      }
      w[i] = w[i - 8] ^ temp;
    }

    return w;
  }

  static int _rotWord(int w) {
    return ((w << 8) & 0xffffffff) | ((w >> 24) & 0xff);
  }

  static int _subWord(int w) {
    return (_sBox[(w >> 24) & 0xff] << 24) |
        (_sBox[(w >> 16) & 0xff] << 16) |
        (_sBox[(w >> 8) & 0xff] << 8) |
        _sBox[w & 0xff];
  }

  static int _gMul(int a, int b) {
    var p = 0;
    var hiBit = 0;
    for (var counter = 0; counter < 8; counter++) {
      if ((b & 1) != 0) {
        p ^= a;
      }
      hiBit = (a & 0x80);
      a = (a << 1) & 0xff;
      if (hiBit != 0) {
        a ^= 0x1b;
      }
      b >>= 1;
    }
    return p;
  }

  static void _encryptBlock(Uint8List block, Uint32List w) {
    final state = Uint8List(16);
    state.setAll(0, block);

    // Initial Round
    _addRoundKey(state, w, 0);

    // Rounds 1 to 13
    for (var round = 1; round < 14; round++) {
      _subBytes(state);
      _shiftRows(state);
      _mixColumns(state);
      _addRoundKey(state, w, round);
    }

    // Round 14 (Final - MixColumns yok)
    _subBytes(state);
    _shiftRows(state);
    _addRoundKey(state, w, 14);

    block.setAll(0, state);
  }

  static void _decryptBlock(Uint8List block, Uint32List w) {
    final state = Uint8List(16);
    state.setAll(0, block);

    // Initial Round (w[14])
    _addRoundKey(state, w, 14);

    // Rounds 13 down to 1
    for (var round = 13; round >= 1; round--) {
      _invShiftRows(state);
      _invSubBytes(state);
      _addRoundKey(state, w, round);
      _invMixColumns(state);
    }

    // Final Round
    _invShiftRows(state);
    _invSubBytes(state);
    _addRoundKey(state, w, 0);

    block.setAll(0, state);
  }

  static void _addRoundKey(Uint8List state, Uint32List w, int round) {
    final base = round * 4;
    for (var c = 0; c < 4; c++) {
      final word = w[base + c];
      state[c * 4 + 0] ^= (word >> 24) & 0xff;
      state[c * 4 + 1] ^= (word >> 16) & 0xff;
      state[c * 4 + 2] ^= (word >> 8) & 0xff;
      state[c * 4 + 3] ^= word & 0xff;
    }
  }

  static void _subBytes(Uint8List state) {
    for (var i = 0; i < 16; i++) {
      state[i] = _sBox[state[i]];
    }
  }

  static void _invSubBytes(Uint8List state) {
    for (var i = 0; i < 16; i++) {
      state[i] = _invSBox[state[i]];
    }
  }

  static void _shiftRows(Uint8List s) {
    // Row 1: << 1
    final t1 = s[1];
    s[1] = s[5];
    s[5] = s[9];
    s[9] = s[13];
    s[13] = t1;
    // Row 2: << 2
    final t2 = s[2];
    final t6 = s[6];
    s[2] = s[10];
    s[6] = s[14];
    s[10] = t2;
    s[14] = t6;
    // Row 3: << 3
    final t3 = s[15];
    s[15] = s[11];
    s[11] = s[7];
    s[7] = s[3];
    s[3] = t3;
  }

  static void _invShiftRows(Uint8List s) {
    // Row 1: >> 1
    final t1 = s[13];
    s[13] = s[9];
    s[9] = s[5];
    s[5] = s[1];
    s[1] = t1;
    // Row 2: >> 2
    final t2 = s[10];
    final t6 = s[14];
    s[10] = s[2];
    s[14] = s[6];
    s[2] = t2;
    s[6] = t6;
    // Row 3: >> 3
    final t3 = s[3];
    s[3] = s[7];
    s[7] = s[11];
    s[11] = s[15];
    s[15] = t3;
  }

  static void _mixColumns(Uint8List s) {
    for (var c = 0; c < 4; c++) {
      final i = c * 4;
      final a0 = s[i];
      final a1 = s[i + 1];
      final a2 = s[i + 2];
      final a3 = s[i + 3];

      s[i] = _gMul(2, a0) ^ _gMul(3, a1) ^ a2 ^ a3;
      s[i + 1] = a0 ^ _gMul(2, a1) ^ _gMul(3, a2) ^ a3;
      s[i + 2] = a0 ^ a1 ^ _gMul(2, a2) ^ _gMul(3, a3);
      s[i + 3] = _gMul(3, a0) ^ a1 ^ a2 ^ _gMul(2, a3);
    }
  }

  static void _invMixColumns(Uint8List s) {
    for (var c = 0; c < 4; c++) {
      final i = c * 4;
      final a0 = s[i];
      final a1 = s[i + 1];
      final a2 = s[i + 2];
      final a3 = s[i + 3];

      s[i] = _gMul(0x0e, a0) ^ _gMul(0x0b, a1) ^ _gMul(0x0d, a2) ^ _gMul(0x09, a3);
      s[i + 1] = _gMul(0x09, a0) ^ _gMul(0x0e, a1) ^ _gMul(0x0b, a2) ^ _gMul(0x0d, a3);
      s[i + 2] = _gMul(0x0d, a0) ^ _gMul(0x09, a1) ^ _gMul(0x0e, a2) ^ _gMul(0x0b, a3);
      s[i + 3] = _gMul(0x0b, a0) ^ _gMul(0x0d, a1) ^ _gMul(0x09, a2) ^ _gMul(0x0e, a3);
    }
  }
}

