import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as cg;
import 'package:path/path.dart' as p;

import 'backup_crypto.dart';
import 'backup_manifest.dart';
import 'database_backup_engine.dart';

class _SingleDigestSink implements Sink<crypto.Digest> {
  crypto.Digest? digest;

  @override
  void add(crypto.Digest data) {
    digest = data;
  }

  @override
  void close() {}
}

/// İncelenen `.mmsbak` paketinin sürüm bağımsız üstverisi (`MMSBAK01` / `MMSBAK02`).
class InspectedBackupPackage {
  final int formatVersion;
  final BackupManifest manifest;
  final int totalBytes;

  const InspectedBackupPackage({
    required this.formatVersion,
    required this.manifest,
    required this.totalBytes,
  });
}

/// Taşınabilir `MMSBAK02` başlık verisi.
class _MmsbakV2Header {
  final int version;
  final int kdfIterations;
  final Uint8List salt;
  final Uint8List noncePrefix;
  final int chunkSize;
  final int plaintextSize;
  final String plaintextSha256;
  final BackupManifest manifest;

  const _MmsbakV2Header({
    required this.version,
    required this.kdfIterations,
    required this.salt,
    required this.noncePrefix,
    required this.chunkSize,
    required this.plaintextSize,
    required this.plaintextSha256,
    required this.manifest,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'format': 'MMSBAK02',
        'algorithm': MmsbakV2Crypto.algorithmId,
        'kdf_iterations': kdfIterations,
        'salt_b64': base64Encode(salt),
        'nonce_prefix_b64': base64Encode(noncePrefix),
        'chunk_size': chunkSize,
        'plaintext_size': plaintextSize,
        'plaintext_sha256': plaintextSha256,
        'manifest': manifest.toJson(),
      };

  factory _MmsbakV2Header.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int || version != MmsbakV2Crypto.formatVersion) {
      throw const BackupCryptoException(
          'Desteklenmeyen MMSBAK02 başlık sürümü.');
    }
    final format = json['format'];
    if (format != 'MMSBAK02') {
      throw const BackupCryptoException('Geçersiz MMSBAK02 format imzası.');
    }
    final kdfIterations = json['kdf_iterations'];
    if (kdfIterations is! int || kdfIterations < 1) {
      throw const BackupCryptoException('Geçersiz PBKDF2 iterasyon sayısı.');
    }
    final salt = Uint8List.fromList(base64Decode(json['salt_b64'] as String));
    final noncePrefix =
        Uint8List.fromList(base64Decode(json['nonce_prefix_b64'] as String));
    if (salt.length != 16 || noncePrefix.length != 8) {
      throw const BackupCryptoException('MMSBAK02 tuz/nonce boyutu geçersiz.');
    }
    final chunkSize = json['chunk_size'];
    if (chunkSize is! int || chunkSize < 1024 || chunkSize > 16 * 1024 * 1024) {
      throw const BackupCryptoException('MMSBAK02 parça boyutu geçersiz.');
    }
    final plaintextSize = json['plaintext_size'];
    if (plaintextSize is! int || plaintextSize < 0) {
      throw const BackupCryptoException('MMSBAK02 düz metin boyutu geçersiz.');
    }
    final shaHex = json['plaintext_sha256'];
    if (shaHex is! String || shaHex.length != 64) {
      throw const BackupCryptoException('MMSBAK02 SHA-256 özeti geçersiz.');
    }
    final manifestJson = json['manifest'];
    if (manifestJson is! Map) {
      throw const BackupCryptoException('MMSBAK02 manifest alanı eksik.');
    }
    final manifest =
        BackupManifest.fromJson(Map<String, dynamic>.from(manifestJson));

    return _MmsbakV2Header(
      version: version,
      kdfIterations: kdfIterations,
      salt: salt,
      noncePrefix: noncePrefix,
      chunkSize: chunkSize,
      plaintextSize: plaintextSize,
      plaintextSha256: shaHex.toLowerCase(),
      manifest: manifest,
    );
  }
}

/// Faz B-1 (`ADR-023`, `OV-05`): Akışlı AEAD + DEK/KEK zarflamalı taşınabilir `MMSBAK02`
/// yedek şifreleme ve `MMSBAK01` geriye dönük çözme/inceleme motoru.
///
/// İkili düzen:
/// `[8B "MMSBAK02"][4B headerLen BE][headerJson UTF-8][12B wrapNonce][32B wrappedDek][16B wrapMac][chunk frames...]`
/// Her chunk çerçevesi: `[4B cipherLen BE][16B mac][ciphertext]`.
class MmsbakV2Crypto {
  static const List<int> magicHeader = [
    0x4D, 0x4D, 0x53, 0x42, 0x41, 0x4B, 0x30, 0x32, // 'MMSBAK02'
  ];
  static const int formatVersion = 2;
  static const String algorithmId = 'AES-256-GCM-DEK-PBKDF2-HMAC-SHA256';
  static const int minPasswordLength = 12;
  static const int defaultPbkdf2Iterations = 600000;
  static const int defaultChunkSize = 1024 * 1024; // 1 MiB
  static const int _wrapHeaderBytes = 12 + 32 + 16; // 60 B
  static const int _gcmNonceBytes = 12;
  static const int _gcmMacBytes = 16;
  static final Random _secureRandom = Random.secure();
  static final cg.AesGcm _aesGcm = cg.AesGcm.with256bits();

  const MmsbakV2Crypto._();

  /// Minimum 12 karakter taşınabilir kurtarma parolasını doğrular (`OV-05`).
  static void validateRecoveryPassword(String password) {
    if (password.length < minPasswordLength) {
      throw const BackupCryptoException(
        'Taşınabilir kurtarma parolası en az $minPasswordLength karakter olmalıdır (parola cümlesi önerilir).',
      );
    }
  }

  /// Düz metin SQLite dosyasını akışlı (O(chunkSize) bellek) olarak `MMSBAK02` dosyasına şifreler.
  static Future<BackupManifest> encryptFile({
    required File inputFile,
    required File outputFile,
    required String password,
    required BackupManifest manifest,
    int kdfIterations = defaultPbkdf2Iterations,
    int chunkSize = defaultChunkSize,
  }) async {
    validateRecoveryPassword(password);
    if (!await inputFile.exists()) {
      throw BackupCryptoException(
          'Şifrelenecek kaynak dosya bulunamadı: ${inputFile.path}');
    }
    if (chunkSize < 1024 || chunkSize > 16 * 1024 * 1024) {
      throw ArgumentError(
          'chunkSize 1024 ile 16 MiB arasında olmalıdır: $chunkSize');
    }
    if (kdfIterations < 1) {
      throw ArgumentError('kdfIterations pozitif olmalıdır: $kdfIterations');
    }

    final plaintextSize = await inputFile.length();
    final plaintextSha256 = await computeFileSha256(inputFile);
    final chunkCount =
        plaintextSize == 0 ? 1 : ((plaintextSize + chunkSize - 1) ~/ chunkSize);
    final totalEncryptedStreamBytes =
        plaintextSize + (chunkCount * (4 + _gcmMacBytes));

    final finalizedManifest = manifest.copyWith(
      checksum: plaintextSha256,
      unencryptedSizeBytes: plaintextSize,
      encryptedSizeBytes: totalEncryptedStreamBytes,
      encryptionAlgorithm: algorithmId,
      kdfIterations: kdfIterations,
    );

    final salt = _randomBytes(16);
    final noncePrefix = _randomBytes(8);
    final dekBytes = _randomBytes(32);
    final wrapNonce = _randomBytes(_gcmNonceBytes);

    final header = _MmsbakV2Header(
      version: formatVersion,
      kdfIterations: kdfIterations,
      salt: salt,
      noncePrefix: noncePrefix,
      chunkSize: chunkSize,
      plaintextSize: plaintextSize,
      plaintextSha256: plaintextSha256,
      manifest: finalizedManifest,
    );
    final headerBytes =
        Uint8List.fromList(utf8.encode(jsonEncode(header.toJson())));
    final headerHash =
        Uint8List.fromList(crypto.sha256.convert(headerBytes).bytes);

    final kek = await _deriveKek(
      password: password,
      salt: salt,
      iterations: kdfIterations,
    );
    final dekKey = cg.SecretKey(dekBytes);

    final wrapBox = await _aesGcm.encrypt(
      dekBytes,
      secretKey: kek,
      nonce: wrapNonce,
      aad: _wrapAad(headerHash),
    );

    if (!await outputFile.parent.exists()) {
      await outputFile.parent.create(recursive: true);
    }
    final tmpFile = File('${outputFile.path}.tmp');
    if (await tmpFile.exists()) {
      await tmpFile.delete();
    }

    RandomAccessFile? reader;
    RandomAccessFile? writer;
    try {
      reader = await inputFile.open(mode: FileMode.read);
      writer = await tmpFile.open(mode: FileMode.write);

      await writer.writeFrom(magicHeader);
      await writer.writeFrom(_uint32Be(headerBytes.length));
      await writer.writeFrom(headerBytes);
      await writer.writeFrom(wrapNonce);
      await writer.writeFrom(wrapBox.cipherText);
      await writer.writeFrom(wrapBox.mac.bytes);

      if (plaintextSize == 0) {
        final chunkBox = await _aesGcm.encrypt(
          const <int>[],
          secretKey: dekKey,
          nonce: _chunkNonce(noncePrefix, 0),
          aad: _chunkAad(headerHash, 0, true),
        );
        await writer.writeFrom(_uint32Be(chunkBox.cipherText.length));
        await writer.writeFrom(chunkBox.mac.bytes);
        await writer.writeFrom(chunkBox.cipherText);
      } else {
        var offset = 0;
        var chunkIndex = 0;
        final buffer = Uint8List(chunkSize);
        while (offset < plaintextSize) {
          final remaining = plaintextSize - offset;
          final toRead = remaining < chunkSize ? remaining : chunkSize;
          final readCount = await reader.readInto(buffer, 0, toRead);
          if (readCount <= 0) {
            throw const BackupCryptoException(
                'Kaynak dosya şifreleme sırasında beklenmedik biçimde kısaldı.');
          }
          offset += readCount;
          final isFinal = offset >= plaintextSize;
          final plainSlice = Uint8List.sublistView(buffer, 0, readCount);
          final chunkBox = await _aesGcm.encrypt(
            plainSlice,
            secretKey: dekKey,
            nonce: _chunkNonce(noncePrefix, chunkIndex),
            aad: _chunkAad(headerHash, chunkIndex, isFinal),
          );
          await writer.writeFrom(_uint32Be(chunkBox.cipherText.length));
          await writer.writeFrom(chunkBox.mac.bytes);
          await writer.writeFrom(chunkBox.cipherText);
          chunkIndex++;
        }
      }

      await writer.flush();
      await writer.close();
      writer = null;
      await reader.close();
      reader = null;

      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      await tmpFile.rename(outputFile.path);
      return finalizedManifest;
    } catch (_) {
      await _safeClose(writer);
      await _safeClose(reader);
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (delErr) {
          stderr.writeln(
            '[MmsbakV2Crypto] Şifreleme geçici dosyası silinemedi (${p.basename(tmpFile.path)}): ${delErr.runtimeType}',
          );
        }
      }
      rethrow;
    }
  }

  /// Şifreli `.mmsbak` dosyasını çözer (`MMSBAK02` akışlı + `MMSBAK01` geriye dönük uyumlu)
  /// ve yalnızca tüm MAC + SHA-256 doğrulamaları geçerse [outputFile] konumuna yazar.
  static Future<BackupManifest> decryptFile({
    required File inputFile,
    required File outputFile,
    required String password,
  }) async {
    if (!await inputFile.exists()) {
      throw BackupCryptoException(
          'Yedek dosyası bulunamadı: ${inputFile.path}');
    }
    final fileSize = await inputFile.length();
    if (fileSize < 32) {
      throw const BackupCryptoException(
          'Yedek dosyası geçersiz veya çok küçük.');
    }

    final headerPreview = await _readRange(inputFile, 0, 8);
    if (_bytesEqual(headerPreview, BackupCryptoService.magicHeader)) {
      final bytes = await inputFile.readAsBytes();
      final decrypted = BackupCryptoService.verifyAndDecryptPackage(
        packageBytes: bytes,
        password: password,
      );
      await _writeTempAndRename(outputFile, decrypted.databaseBytes);
      return decrypted.manifest;
    }

    if (!_bytesEqual(headerPreview, magicHeader)) {
      throw const BackupCryptoException(
          'Geçersiz yedek dosyası formatı (MMSBAK01/MMSBAK02 değil).');
    }
    if (password.isEmpty) {
      throw const BackupCryptoException('Yedek çözme parolası boş olamaz.');
    }

    RandomAccessFile? reader;
    RandomAccessFile? writer;
    final tmpOut = File('${outputFile.path}.tmp');
    try {
      reader = await inputFile.open(mode: FileMode.read);
      final parsed = await _readAndValidateV2HeaderFromRaf(reader, fileSize);
      final kek = await _deriveKek(
        password: password,
        salt: parsed.header.salt,
        iterations: parsed.header.kdfIterations,
      );

      final wrapBuf = await _readExact(reader, _wrapHeaderBytes);
      final wrapNonce = Uint8List.sublistView(wrapBuf, 0, _gcmNonceBytes);
      final wrappedDek =
          Uint8List.sublistView(wrapBuf, _gcmNonceBytes, _gcmNonceBytes + 32);
      final wrapMac = cg.Mac(
        Uint8List.sublistView(wrapBuf, _gcmNonceBytes + 32, _wrapHeaderBytes),
      );

      final List<int> dekBytes;
      try {
        dekBytes = await _aesGcm.decrypt(
          cg.SecretBox(wrappedDek, nonce: wrapNonce, mac: wrapMac),
          secretKey: kek,
          aad: _wrapAad(parsed.headerHash),
        );
      } catch (e) {
        throw BackupCryptoException(
          'MMSBAK02 bütünlük doğrulaması başarısız veya kurtarma parolası yanlış: $e',
        );
      }

      if (dekBytes.length != 32) {
        throw const BackupCryptoException(
            'Çözülen DEK anahtar boyutu geçersiz.');
      }
      final dekKey = cg.SecretKey(dekBytes);

      if (!await outputFile.parent.exists()) {
        await outputFile.parent.create(recursive: true);
      }
      if (await tmpOut.exists()) {
        await tmpOut.delete();
      }
      writer = await tmpOut.open(mode: FileMode.write);

      final digestSink = _SingleDigestSink();
      final shaSink = crypto.sha256.startChunkedConversion(digestSink);

      final expectedTotal = parsed.header.plaintextSize;
      final expectedChunks = expectedTotal == 0
          ? 1
          : ((expectedTotal + parsed.header.chunkSize - 1) ~/
              parsed.header.chunkSize);

      var totalDecryptedBytes = 0;
      for (var chunkIndex = 0; chunkIndex < expectedChunks; chunkIndex++) {
        final lenBytes = await _readExact(reader, 4);
        final cipherLen = _readUint32Be(lenBytes, 0);
        if (cipherLen < 0 || cipherLen > parsed.header.chunkSize) {
          throw const BackupCryptoException(
              'MMSBAK02 parça uzunluğu geçersiz.');
        }
        final macBytes = await _readExact(reader, _gcmMacBytes);
        final cipherBytes =
            cipherLen == 0 ? Uint8List(0) : await _readExact(reader, cipherLen);

        final isFinal = chunkIndex == expectedChunks - 1;
        final List<int> plainChunk;
        try {
          plainChunk = await _aesGcm.decrypt(
            cg.SecretBox(
              cipherBytes,
              nonce: _chunkNonce(parsed.header.noncePrefix, chunkIndex),
              mac: cg.Mac(macBytes),
            ),
            secretKey: dekKey,
            aad: _chunkAad(parsed.headerHash, chunkIndex, isFinal),
          );
        } catch (e) {
          throw BackupCryptoException(
            'MMSBAK02 parça #$chunkIndex AEAD doğrulaması başarısız (veri bozulmuş): $e',
          );
        }

        totalDecryptedBytes += plainChunk.length;
        if (plainChunk.isNotEmpty) {
          shaSink.add(plainChunk);
          await writer.writeFrom(plainChunk);
        }
      }

      final currentPos = await reader.position();
      if (currentPos != fileSize) {
        throw const BackupCryptoException(
          'MMSBAK02 dosya sonunda beklenmeyen ekstra veri tespit edildi.',
        );
      }
      if (totalDecryptedBytes != expectedTotal) {
        throw BackupCryptoException(
          'Çözülen boyut başlık ile uyuşmuyor ($totalDecryptedBytes != $expectedTotal).',
        );
      }

      shaSink.close();
      final actualSha = digestSink.digest.toString().toLowerCase();
      if (actualSha != parsed.header.plaintextSha256) {
        throw BackupCryptoException(
          'Çözülen veritabanı SHA-256 özeti uyuşmuyor (${parsed.header.plaintextSha256} != $actualSha).',
        );
      }

      await writer.flush();
      await writer.close();
      writer = null;
      await reader.close();
      reader = null;

      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      await tmpOut.rename(outputFile.path);
      return parsed.header.manifest;
    } catch (_) {
      await _safeClose(writer);
      await _safeClose(reader);
      if (await tmpOut.exists()) {
        try {
          await tmpOut.delete();
        } catch (delErr) {
          stderr.writeln(
            '[MmsbakV2Crypto] Çözme geçici dosyası silinemedi (${p.basename(tmpOut.path)}): ${delErr.runtimeType}',
          );
        }
      }
      rethrow;
    }
  }

  /// Parola gerektirmeden `MMSBAK02` veya `MMSBAK01` dosya yapısını ve manifestini doğrular.
  static Future<InspectedBackupPackage> inspectFile(File file) async {
    if (!await file.exists()) {
      throw BackupException(
          'ERR_BACKUP_NOT_FOUND', 'Yedek dosyası bulunamadı: ${file.path}');
    }
    final fileSize = await file.length();
    if (fileSize < 12) {
      throw const BackupException(
          'ERR_CORRUPT_BACKUP', 'Yedek dosyası çok küçük veya bozuk.');
    }

    final magic = await _readRange(file, 0, 8);
    if (_bytesEqual(magic, BackupCryptoService.magicHeader)) {
      final bytes = await file.readAsBytes();
      final manifest =
          BackupCryptoService.extractManifestWithoutDecryption(bytes);
      final manifestLen =
          (bytes[8] << 24) | (bytes[9] << 16) | (bytes[10] << 8) | bytes[11];
      final expected =
          12 + manifestLen + 16 + 16 + manifest.encryptedSizeBytes + 32;
      if (manifest.encryptedSizeBytes <= 0 || bytes.length != expected) {
        throw BackupException(
          'ERR_INCOMPLETE_BACKUP',
          'Yedek dosyası eksik (beklenen $expected bayt, bulunan ${bytes.length}).',
        );
      }
      return InspectedBackupPackage(
        formatVersion: 1,
        manifest: manifest,
        totalBytes: fileSize,
      );
    }

    if (_bytesEqual(magic, magicHeader)) {
      final reader = await file.open(mode: FileMode.read);
      try {
        final parsed = await _readAndValidateV2HeaderFromRaf(reader, fileSize);
        return InspectedBackupPackage(
          formatVersion: 2,
          manifest: parsed.header.manifest,
          totalBytes: fileSize,
        );
      } finally {
        await reader.close();
      }
    }

    throw const BackupException(
        'ERR_CORRUPT_BACKUP', 'Geçerli MMSBAK01/MMSBAK02 başlığı bulunamadı.');
  }

  /// Bellek içi tampon üzerinde `MMSBAK01` veya `MMSBAK02` yapısal doğrulaması yapar.
  static InspectedBackupPackage verifyBytesStructure(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const BackupException(
          'ERR_CORRUPT_BACKUP', 'Yedek paketi çok küçük.');
    }
    final magic = bytes.sublist(0, 8);
    if (_bytesEqual(magic, BackupCryptoService.magicHeader)) {
      final manifest =
          BackupCryptoService.extractManifestWithoutDecryption(bytes);
      final manifestLen = _readUint32Be(bytes, 8);
      final expected =
          12 + manifestLen + 16 + 16 + manifest.encryptedSizeBytes + 32;
      if (manifest.encryptedSizeBytes <= 0 || bytes.length != expected) {
        throw BackupException(
          'ERR_INCOMPLETE_BACKUP',
          'Yedek dosyası eksik veya yarım kopyalanmış (beklenen $expected bayt, bulunan ${bytes.length}).',
        );
      }
      return InspectedBackupPackage(
        formatVersion: 1,
        manifest: manifest,
        totalBytes: bytes.length,
      );
    }

    if (_bytesEqual(magic, magicHeader)) {
      final headerLen = _readUint32Be(bytes, 8);
      if (headerLen <= 0 || 12 + headerLen + _wrapHeaderBytes > bytes.length) {
        throw const BackupException(
            'ERR_CORRUPT_BACKUP', 'MMSBAK02 başlığı bozuk veya eksik.');
      }
      final headerBytes = Uint8List.sublistView(bytes, 12, 12 + headerLen);
      final header = _parseHeaderBytes(headerBytes);
      final expected = _expectedTotalFileBytes(headerLen, header);
      if (bytes.length != expected) {
        throw BackupException(
          'ERR_INCOMPLETE_BACKUP',
          'MMSBAK02 dosyası eksik (beklenen $expected bayt, bulunan ${bytes.length}).',
        );
      }
      return InspectedBackupPackage(
        formatVersion: 2,
        manifest: header.manifest,
        totalBytes: bytes.length,
      );
    }

    throw const BackupException(
        'ERR_CORRUPT_BACKUP', 'Geçersiz MMS yedek formatı.');
  }

  static Future<String> computeFileSha256(File file) async {
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  static Future<cg.SecretKey> _deriveKek({
    required String password,
    required Uint8List salt,
    required int iterations,
  }) {
    final pbkdf2 = cg.Pbkdf2(
      macAlgorithm: cg.Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
  }

  static List<int> _wrapAad(Uint8List headerHash) => <int>[
        ...utf8.encode('MMSBAK02:WRAP:'),
        ...headerHash,
      ];

  static Uint8List _chunkNonce(Uint8List prefix, int chunkIndex) {
    final nonce = Uint8List(_gcmNonceBytes);
    nonce.setRange(0, 8, prefix);
    nonce[8] = (chunkIndex >> 24) & 0xff;
    nonce[9] = (chunkIndex >> 16) & 0xff;
    nonce[10] = (chunkIndex >> 8) & 0xff;
    nonce[11] = chunkIndex & 0xff;
    return nonce;
  }

  static Uint8List _chunkAad(
      Uint8List headerHash, int chunkIndex, bool isFinal) {
    final aad = Uint8List(headerHash.length + 5);
    aad.setRange(0, headerHash.length, headerHash);
    aad[headerHash.length] = (chunkIndex >> 24) & 0xff;
    aad[headerHash.length + 1] = (chunkIndex >> 16) & 0xff;
    aad[headerHash.length + 2] = (chunkIndex >> 8) & 0xff;
    aad[headerHash.length + 3] = chunkIndex & 0xff;
    aad[headerHash.length + 4] = isFinal ? 1 : 0;
    return aad;
  }

  static int _expectedTotalFileBytes(int headerLen, _MmsbakV2Header header) {
    final chunkCount = header.plaintextSize == 0
        ? 1
        : ((header.plaintextSize + header.chunkSize - 1) ~/ header.chunkSize);
    final streamBytes =
        header.plaintextSize + (chunkCount * (4 + _gcmMacBytes));
    return 12 + headerLen + _wrapHeaderBytes + streamBytes;
  }

  static _MmsbakV2Header _parseHeaderBytes(Uint8List headerBytes) {
    try {
      final decoded = jsonDecode(utf8.decode(headerBytes));
      if (decoded is! Map) {
        throw const FormatException('Başlık JSON nesnesi değil');
      }
      return _MmsbakV2Header.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      throw BackupException(
          'ERR_CORRUPT_BACKUP', 'MMSBAK02 başlığı okunamadı: $e');
    }
  }

  static Future<({_MmsbakV2Header header, Uint8List headerHash})>
      _readAndValidateV2HeaderFromRaf(
    RandomAccessFile reader,
    int fileSize,
  ) async {
    await reader.setPosition(8);
    final lenBytes = await _readExact(reader, 4);
    final headerLen = _readUint32Be(lenBytes, 0);
    if (headerLen <= 0 ||
        headerLen > 1024 * 1024 ||
        12 + headerLen + _wrapHeaderBytes > fileSize) {
      throw const BackupException(
          'ERR_CORRUPT_BACKUP', 'MMSBAK02 başlık uzunluğu geçersiz.');
    }
    final headerBytes = await _readExact(reader, headerLen);
    final header = _parseHeaderBytes(headerBytes);
    final expected = _expectedTotalFileBytes(headerLen, header);
    if (fileSize != expected) {
      throw BackupException(
        'ERR_INCOMPLETE_BACKUP',
        'MMSBAK02 dosya boyutu tutarsız (beklenen $expected, gerçek $fileSize).',
      );
    }
    final headerHash =
        Uint8List.fromList(crypto.sha256.convert(headerBytes).bytes);
    return (header: header, headerHash: headerHash);
  }

  static Future<Uint8List> _readRange(File file, int start, int length) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(start);
      return await _readExact(raf, length);
    } finally {
      await raf.close();
    }
  }

  static Future<Uint8List> _readExact(RandomAccessFile raf, int length) async {
    final buf = Uint8List(length);
    var offset = 0;
    while (offset < length) {
      final n = await raf.readInto(buf, offset, length);
      if (n <= 0) {
        throw const BackupException(
            'ERR_INCOMPLETE_BACKUP', 'Yedek dosyası beklenmeden sona erdi.');
      }
      offset += n;
    }
    return buf;
  }

  static Future<void> _writeTempAndRename(File target, Uint8List bytes) async {
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    final tmp =
        File(p.join(target.parent.path, '${p.basename(target.path)}.tmp'));
    await tmp.writeAsBytes(bytes, flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    await tmp.rename(target.path);
  }

  static Future<void> _safeClose(RandomAccessFile? raf) async {
    if (raf == null) return;
    try {
      await raf.close();
    } catch (e) {
      stderr.writeln(
        '[MmsbakV2Crypto] Dosya tutamacı kapatma uyarısı: ${e.runtimeType}',
      );
    }
  }

  static Uint8List _randomBytes(int len) => Uint8List.fromList(
      List<int>.generate(len, (_) => _secureRandom.nextInt(256)));

  static Uint8List _uint32Be(int v) => Uint8List.fromList([
        (v >> 24) & 0xff,
        (v >> 16) & 0xff,
        (v >> 8) & 0xff,
        v & 0xff,
      ]);

  static int _readUint32Be(List<int> b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
