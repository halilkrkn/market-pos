import 'dart:io';

/// Sabitlenen parmak izi uyuşmazlığının sınıflandırma nedeni (ADR-017).
enum TlsPinMismatchReason {
  pinOrCaMismatch,
  untrustedCaChain,
  leafPinMismatch,
}

/// Faz 7B — Hub'ın sunduğu TLS sertifikası, eşleştirmede sabitlenen (pinned)
/// SHA-256 parmak iziyle uyuşmadığında fırlatılır.
///
/// Sıradan ağ hatası DEĞİLDİR: yanlış Hub, sertifika rotasyonu veya ortadaki adam
/// (MITM) saldırısı anlamına gelebilir. İstek gövdesi ve `Authorization` başlığı
/// TLS el sıkışması tamamlanmadığı için sunucuya hiç gönderilmez.
class TlsPinMismatchException implements IOException {
  final String host;
  final int port;

  /// Sunucunun sunduğu yaprak sertifikanın SHA-256 parmak izi (büyük harf hex).
  /// Gizli değildir; Owner'ın yeni sertifikayı doğrulaması için gösterilir.
  final String presentedSha256;

  /// Pin/CA uyuşmazlığının teknik nedeni.
  final TlsPinMismatchReason reason;

  const TlsPinMismatchException({
    required this.host,
    required this.port,
    required this.presentedSha256,
    this.reason = TlsPinMismatchReason.pinOrCaMismatch,
  });

  String get message =>
      'Hub TLS sertifikası eşleştirmede sabitlenen parmak iziyle uyuşmuyor ($host:$port). '
      'Sunulan SHA-256: $presentedSha256. Bağlantı güvenlik nedeniyle reddedildi; '
      'Hub sertifikası yenilendiyse cihazı yeniden eşleştirin, aksi halde ağı kontrol edin.';

  @override
  String toString() => 'TlsPinMismatchException(${reason.name}): $message';
}

/// ADR-017: Güvenilen kök CA altındaki yaprak sertifika doğrulama hatası türleri.
enum TlsCertificateFailureKind {
  ipAddressMismatch,
  hostnameMismatch,
  certificateExpired,
  certificateNotYetValid,
  handshakeError,
}

/// ADR-017: Kök CA güven zinciri dışındaki TLS sertifika doğrulama hataları
/// (SAN/IP uyuşmazlığı, hostname uyuşmazlığı, süresi dolmuş sertifika).
///
/// Pin uyuşmazlığı ([TlsPinMismatchException]) ile karıştırılmaz; ancak güvenlik
/// gereği fail-closed kalır (HTTP fallback yapılmaz).
class TlsCertificateValidationException implements IOException {
  final TlsCertificateFailureKind kind;
  final String host;
  final int port;
  final String? presentedSha256;
  final String? detail;

  const TlsCertificateValidationException({
    required this.kind,
    required this.host,
    required this.port,
    this.presentedSha256,
    this.detail,
  });

  String get message => switch (kind) {
        TlsCertificateFailureKind.ipAddressMismatch =>
          'Hub TLS sertifikası bağlantı IP adresini (SAN) doğrulamadı ($host:$port). '
              'Sertifikanın IP SAN alanını veya Hub IP yapılandırmasını kontrol edin.',
        TlsCertificateFailureKind.hostnameMismatch =>
          'Hub TLS sertifikası sunucu adını (Hostname/SAN) doğrulamadı ($host:$port). '
              'Sertifika DNS/SAN alanını kontrol edin.',
        TlsCertificateFailureKind.certificateExpired =>
          'Hub TLS sertifikasının süresi dolmuş ($host:$port). '
              'Hub sertifikasını aynı kök CA ile yenileyin.',
        TlsCertificateFailureKind.certificateNotYetValid =>
          'Hub TLS sertifikası henüz geçerli değil ($host:$port). '
              'Hub ve cihaz sistem saatini kontrol edin.',
        TlsCertificateFailureKind.handshakeError =>
          'Hub TLS sertifika doğrulaması başarısız ($host:$port).',
      };

  @override
  String toString() =>
      'TlsCertificateValidationException(${kind.name}): $message';
}
