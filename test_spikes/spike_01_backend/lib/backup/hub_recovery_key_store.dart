import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mms_client_storage/mms_client_storage.dart';

import 'hub_backup_oauth_store.dart';

class HubRecoveryKeyException implements Exception {
  final String code;
  final String message;

  const HubRecoveryKeyException(this.code, this.message);

  @override
  String toString() => 'HubRecoveryKeyException [$code]: $message';
}

/// `OV-01` & `OV-05`: Katılımsız zamanlanmış yedeklemeler için 12+ karakterli
/// kurtarma anahtarını LocalMachine DPAPI + alan-ayrımlı `pOptionalEntropy` ile
/// `<securityDir>/backup_recovery_key.dpapi` altında saklar.
///
/// Kural: Asla düz metin dosyasına yazılmaz, loglanmaz, API status cevabında
/// döndürülmez ve Google Drive'a yüklenmez.
class HubRecoveryKeyStore {
  static const String defaultFileName = 'backup_recovery_key.dpapi';
  static final List<int> recoveryKeyEntropy =
      utf8.encode('MarketMMS:HubBackupRecoveryKey:v1');

  final File file;
  final HubSecretCipher cipher;

  HubRecoveryKeyStore(
    this.file, {
    HubSecretCipher? cipher,
  }) : cipher = cipher ?? const WindowsDpapiEntropyCipher();

  Future<void> saveRecoveryPassword(String password) async {
    try {
      MmsbakV2Crypto.validateRecoveryPassword(password);
    } on BackupCryptoException catch (e) {
      throw HubRecoveryKeyException('ERR_WEAK_RECOVERY_PASSWORD', e.message);
    }

    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final cipherBytes = cipher.protect(utf8.encode(password), recoveryKeyEntropy);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(cipherBytes, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  Future<String?> loadRecoveryPassword() async {
    if (!await file.exists()) return null;
    final encrypted = await file.readAsBytes();
    if (encrypted.isEmpty) {
      throw const HubRecoveryKeyException(
        'ERR_CORRUPT_RECOVERY_KEY',
        'Katılımsız yedekleme kurtarma anahtarı dosyası boş veya bozuk.',
      );
    }
    final Uint8List plainBytes;
    try {
      plainBytes = cipher.unprotect(encrypted, recoveryKeyEntropy);
    } catch (e) {
      throw HubRecoveryKeyException(
        'ERR_DPAPI_RECOVERY_KEY',
        'Katılımsız yedekleme kurtarma anahtarı çözülemedi: $e',
      );
    }
    final decoded = utf8.decode(plainBytes);
    if (decoded.length < MmsbakV2Crypto.minPasswordLength) {
      throw const HubRecoveryKeyException(
        'ERR_CORRUPT_RECOVERY_KEY',
        'Çözülen kurtarma anahtarı minimum uzunluğu sağlamıyor.',
      );
    }
    return decoded;
  }

  Future<bool> hasRecoveryPassword() => file.exists();

  Future<void> clear() async {
    if (await file.exists()) {
      await file.delete();
    }
    final tmp = File('${file.path}.tmp');
    if (await tmp.exists()) {
      await tmp.delete();
    }
  }
}
