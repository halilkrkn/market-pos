import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dpapi.dart';

class PepperSecurityException implements Exception {
  final String message;
  PepperSecurityException(this.message);

  @override
  String toString() => 'PepperSecurityException: $message';
}

/// Sunucu genelindeki 256-bit pepper (sır) yönetimini sağlayan sınıf.
/// Pepper kesinlikle veritabanında veya kaynak kodda tutulmaz;
/// Windows DPAPI (LocalMachine) ile şifrelenmiş olarak diskte saklanır.
class PepperManager {
  final File file;
  String? _cachedPepper;

  PepperManager(this.file);

  /// Bellekteki aktif pepper değeri
  String get pepper {
    if (_cachedPepper == null) {
      throw PepperSecurityException('Pepper henüz başlatılmadı veya yüklenemedi.');
    }
    return _cachedPepper!;
  }

  /// Servis başlangıcında pepper'ı yükler veya ilk kurulumda güvenli şekilde üretir.
  /// Bozuk veya çözülemeyen durumlarda güvenli olmayan fallback oluşturmaz, hata fırlatır.
  void initialize({String? overrideForTesting}) {
    if (overrideForTesting != null) {
      _cachedPepper = overrideForTesting;
      return;
    }

    if (!file.existsSync()) {
      // 1. Yeni Kurulum: 256-bit (32 byte) kriptografik rastgele pepper üret
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      final rawPepper = base64UrlEncode(bytes).replaceAll('=', '');

      if (Platform.isWindows) {
        final encryptedBytes = WindowsDpapi.protectString(rawPepper);
        if (!file.parent.existsSync()) {
          file.parent.createSync(recursive: true);
        }
        file.writeAsBytesSync(encryptedBytes, flush: true);
      } else {
        // Windows harici platformlarda test amaçlı doğrudan saklama (Windows'ta DPAPI zorunludur)
        if (!file.parent.existsSync()) {
          file.parent.createSync(recursive: true);
        }
        file.writeAsStringSync(rawPepper, flush: true);
      }

      _cachedPepper = rawPepper;
      return;
    }

    // 2. Mevcut Dosyadan Yükleme ve DPAPI Çözümü
    try {
      final fileBytes = file.readAsBytesSync();
      if (fileBytes.isEmpty) {
        throw PepperSecurityException('Pepper dosyası boş.');
      }

      if (Platform.isWindows) {
        _cachedPepper = WindowsDpapi.unprotectString(fileBytes);
      } else {
        _cachedPepper = utf8.decode(fileBytes);
      }

      if (_cachedPepper == null || _cachedPepper!.length < 32) {
        throw PepperSecurityException('Pepper uzunluğu 256-bit entropi sınırını karşılamıyor.');
      }
    } catch (e) {
      _cachedPepper = null;
      // Güvenli olmayan açık metin fallback kesinlikle OLUŞTURULMAZ!
      throw PepperSecurityException(
        'Kritik Güvenlik Hatası: Pepper DPAPI ile çözülemedi veya bozuk. Servis güvenli şekilde başlatmayı reddetti. ($e)',
      );
    }
  }
}

