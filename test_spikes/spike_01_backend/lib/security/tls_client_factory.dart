import 'dart:io';
import 'certificate_manager.dart';

/// İstemci (Kasa Terminali / Mobil Cihaz) tarafında Kök CA'yı sabitleyen (pin),
/// SHA-256 parmak izi denetimi yapan ve güvenli TLS 1.3 bağlantısı açan fabrika.
class TlsClientFactory {
  /// Yalnızca sağlanan yerel Kök CA'yı güvenilir kabul eden ve işletim sistemi
  /// genel sertifika deposunu dışlayan (withTrustedRoots: false) HttpClient oluşturur.
  static HttpClient createPinnedClient({
    required List<int> trustedRootCaBytes,
    String? expectedFingerprint,
    Duration connectionTimeout = const Duration(seconds: 10),
  }) {
    if (trustedRootCaBytes.isEmpty) {
      throw TlsSecurityException('Root CA sertifikası boş olamaz.');
    }

    // 1. Bant-dışı / QR Güven Çapası (Fingerprint) Doğrulaması
    if (expectedFingerprint != null) {
      final actualFingerprint = CertificateManager.computeSha256Fingerprint(trustedRootCaBytes);
      final normalizedActual = actualFingerprint.replaceAll(':', '').toLowerCase();
      final normalizedExpected = expectedFingerprint.replaceAll(':', '').toLowerCase();

      if (normalizedActual != normalizedExpected) {
        throw TlsSecurityException(
          'Root CA parmak izi uyuşmazlığı tespit edildi! '
          'Beklenen: $expectedFingerprint, Gerçekleşen: $actualFingerprint. '
          'Olası MITM saldırısı nedeniyle bağlantı reddedildi.',
        );
      }
    }

    // 2. Kök sertifikayı sabitle (Pin) ve OS deposunu körü körüne güvenmekten kaçın
    final secContext = SecurityContext(withTrustedRoots: false);
    secContext.setTrustedCertificatesBytes(trustedRootCaBytes);

    final client = HttpClient(context: secContext);
    client.connectionTimeout = connectionTimeout;

    // 3. Katı Red Kuralı: badCertificateCallback ASLA koşulsuz true dönmez!
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      // Geçersiz, süresi dolmuş veya bilinmeyen bir CA tarafından imzalanmış sertifikaları reddet
      return false;
    };

    return client;
  }
}

