import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'dpapi.dart';

class LiveDriveSecretException implements Exception {
  final String message;
  LiveDriveSecretException(this.message);

  @override
  String toString() => 'LiveDriveSecretException: $message';
}

/// K-05 (ADR-021): Hub tarafından tüm eşleştirilmiş mağaza cihazlarına TLS-pinned
/// kanal üzerinden sağlanan paylaşılan 256-bit canlı Drive senkronizasyon gizlisi.
///
/// - `pepper.dpapi` ve `adminSecret` değerlerinden tamamen bağımsızdır.
/// - Windows üzerinde LocalMachine DPAPI ile, Linux/macOS test ortamlarında dosya
///   olarak atomik `.tmp` + rename yöntemiyle saklanır.
/// - Saf bellek içi testler için [LiveDriveSecretManager.inMemory] desteklenir;
///   çalışma dizinine kalıntı dosya bırakmaz.
class LiveDriveSecretManager {
  final File? file;
  final bool _inMemoryOnly;
  String? _cachedSecret;

  LiveDriveSecretManager(File this.file) : _inMemoryOnly = false;

  LiveDriveSecretManager.inMemory({String? initialSecret})
      : file = null,
        _inMemoryOnly = true {
    if (initialSecret != null) {
      final trimmed = initialSecret.trim();
      if (trimmed.length < 32) {
        throw LiveDriveSecretException(
          'Live Drive gizlisi en az 32 karakter (256-bit entropi) olmalıdır.',
        );
      }
      _cachedSecret = trimmed;
    }
  }

  String get secret {
    final current = _cachedSecret;
    if (current == null || current.isEmpty) {
      throw LiveDriveSecretException(
        'Live Drive senkronizasyon gizlisi henüz başlatılmadı veya yüklenemedi.',
      );
    }
    return current;
  }

  static String _generateSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  void _writeAtomic(String rawSecret) {
    final targetFile = file;
    if (targetFile == null) return;
    if (!targetFile.parent.existsSync()) {
      targetFile.parent.createSync(recursive: true);
    }
    final tmpFile = File('${targetFile.path}.tmp');
    final bytes = Platform.isWindows
        ? WindowsDpapi.protectString(rawSecret)
        : utf8.encode(rawSecret);
    tmpFile.writeAsBytesSync(bytes, flush: true);
    if (targetFile.existsSync()) {
      targetFile.deleteSync();
    }
    tmpFile.renameSync(targetFile.path);
  }

  /// Servis başlangıcında gizliyi yükler veya ilk kurulumda kriptografik olarak üretir.
  /// Bozuk veya çözülemeyen dosyalarda zayıf/boş fallback oluşturmaz (fail-closed).
  void initialize({String? overrideForTesting}) {
    if (overrideForTesting != null) {
      final trimmed = overrideForTesting.trim();
      if (trimmed.length < 32) {
        throw LiveDriveSecretException(
          'Test override gizlisi en az 32 karakter olmalıdır.',
        );
      }
      _cachedSecret = trimmed;
      return;
    }

    if (_inMemoryOnly || file == null) {
      _cachedSecret ??= _generateSecret();
      return;
    }

    final targetFile = file!;
    if (!targetFile.existsSync()) {
      final generated = _generateSecret();
      _writeAtomic(generated);
      _cachedSecret = generated;
      return;
    }

    try {
      final fileBytes = targetFile.readAsBytesSync();
      if (fileBytes.isEmpty) {
        throw LiveDriveSecretException('Live Drive gizli dosyası boş.');
      }

      final decoded = Platform.isWindows
          ? WindowsDpapi.unprotectString(fileBytes)
          : utf8.decode(fileBytes);
      final trimmed = decoded.trim();
      if (trimmed.length < 32) {
        throw LiveDriveSecretException(
          'Live Drive gizlisi 256-bit entropi sınırını karşılamıyor.',
        );
      }
      _cachedSecret = trimmed;
    } catch (e) {
      _cachedSecret = null;
      if (e is LiveDriveSecretException) rethrow;
      throw LiveDriveSecretException(
        'Kritik Güvenlik Hatası: Live Drive gizlisi DPAPI ile çözülemedi veya bozuk. ($e)',
      );
    }
  }

  /// Yönetici talebiyle 256-bit yeni gizli üretip atomik olarak kalıcılaştırır.
  String rotate() {
    final next = _generateSecret();
    if (!_inMemoryOnly && file != null) {
      _writeAtomic(next);
    }
    _cachedSecret = next;
    return next;
  }
}
