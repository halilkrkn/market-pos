import 'dart:io';
import 'dart:typed_data';
import 'package:mms_client_storage/mms_client_storage.dart';
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

    final CanonicalCertDerResult canonical;
    try {
      canonical = extractCanonicalSingleCertDer(
        Uint8List.fromList(trustedRootCaBytes),
      );
      MmsX509PreValidator.validateRootCaDer(canonical.derBytes);
    } on X509ValidationException catch (e) {
      throw TlsSecurityException('Geçersiz Root CA sertifikası (${e.code}): ${e.message}');
    }

    // 1. Bant-dışı / QR Güven Çapası (Fingerprint) Doğrulaması
    if (expectedFingerprint != null) {
      final normalizedActual = canonical.sha256Hex;
      final normalizedExpected = expectedFingerprint.replaceAll(':', '').replaceAll(' ', '').trim().toUpperCase();

      if (!constantTimeEqualsAscii(normalizedActual, normalizedExpected)) {
        throw TlsSecurityException(
          'Root CA parmak izi uyuşmazlığı tespit edildi! '
          'Beklenen: $expectedFingerprint, Gerçekleşen: ${CertificateManager.formatSha256Colon(normalizedActual)}. '
          'Olası MITM saldırısı nedeniyle bağlantı reddedildi.',
        );
      }
    }

    // 2. Kök sertifikayı sabitle (Pin) ve OS deposunu körü körüne güvenmekten kaçın
    final secContext = SecurityContext(withTrustedRoots: false);
    secContext.setTrustedCertificatesBytes(canonical.toPemBytes());

    final client = HttpClient(context: secContext);
    client.connectionTimeout = connectionTimeout;

    // 3. Katı Red Kuralı: badCertificateCallback ASLA koşulsuz true dönmez!
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      return false;
    };

    return client;
  }
}

