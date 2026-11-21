import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mms_client_storage/mms_client_storage.dart'
    show
        CanonicalCertDerResult,
        MmsX509PreValidator,
        TlsCertificateFailureKind,
        TlsCertificateValidationException,
        TlsPinMismatchException,
        TlsPinMismatchReason,
        X509ValidationException,
        computeCanonicalSha256Hex,
        constantTimeEqualsAscii,
        encodeDerCertificateAsPem,
        extractCanonicalSingleCertDer;

/// B-2 Certificate Pinning yapılandırma modeli.
class PinnedTlsConfig {
  final String? caCertPem;
  final String expectedSha256Hex;

  const PinnedTlsConfig({
    this.caCertPem,
    required this.expectedSha256Hex,
  });

  String get normalizedExpectedSha256 => normalizeHex(expectedSha256Hex);

  static String normalizeHex(String raw) {
    return raw.replaceAll(':', '').replaceAll(' ', '').trim().toUpperCase();
  }
}

/// B-2 Kök CA ve SHA-256 sertifika sabitlemeli `http.Client` fabrikası.
///
/// İki katmanlı koruma sağlar:
/// 1) Beklenen SHA-256 parmak izi CA PEM içindeki sertifikayla eşleşiyorsa yalnızca
///    o CA'ya güvenen (`withTrustedRoots: false`) izole [SecurityContext] kurar.
/// 2) Sunucunun sunduğu yaprak sertifikanın parmak izi sabitlenmişse veya zincir
///    doğrulanamazsa, `badCertificateCallback` ile sunulan `X509Certificate.der`
///    özetini sabit zamanlı karşılaştırmayla doğrular ve eşleşmeyen her bağlantıyı
///    HTTP başlıkları/token gönderilmeden reddeder.
class MmsPinnedTlsClientFactory {
  static String computeSha256Hex(List<int> derBytes) =>
      computeCanonicalSha256Hex(derBytes);

  /// Katman 1 + Katman 2 (`P-BLOCK-1`): PEM veya ham DER Root CA girdisini doğrular,
  /// kanonik tekil DER çıktısını ve 64-hex büyük harf SHA-256 parmak izini döner.
  static CanonicalCertDerResult validateAndComputeCaPin(
    Uint8List rawBytes, {
    DateTime? nowUtc,
  }) {
    final canonical = extractCanonicalSingleCertDer(rawBytes);
    MmsX509PreValidator.validateRootCaDer(canonical.derBytes, nowUtc: nowUtc);
    return canonical;
  }

  /// Çoklu CA bundle ayıklaması (eski uyumlu API) — yalnızca sıkı `extractCanonicalSingleCertDer`
  /// veya tekli PEM bloklarıyla geçerli DER döndürür; tek sertifika varsa Katman 1 ile ayrıştırır.
  static List<List<int>> extractPemCertificatesDer(String pem) {
    final certs = <List<int>>[];
    const beginMarker = '-----BEGIN CERTIFICATE-----';
    const endMarker = '-----END CERTIFICATE-----';

    var startIndex = 0;
    while (true) {
      final begin = pem.indexOf(beginMarker, startIndex);
      if (begin == -1) break;
      final end = pem.indexOf(endMarker, begin);
      if (end == -1) break;
      final singleBlock = pem.substring(begin, end + endMarker.length);
      try {
        final canonical = extractCanonicalSingleCertDer(
          Uint8List.fromList(utf8.encode(singleBlock)),
        );
        certs.add(canonical.derBytes);
      } on X509ValidationException {
        // Geçersiz blok atlanır; güvenlik gereği boş güvene düşer.
      }
      startIndex = end + endMarker.length;
    }
    return certs;
  }

  static bool _constantTimeEquals(String a, String b) =>
      constantTimeEqualsAscii(a, b);

  static String _encodeMatchedCertificatesAsPem(
    List<List<int>> derCerts,
    String normalizedPin,
  ) {
    final buffer = StringBuffer();
    for (final der in derCerts) {
      if (!_constantTimeEquals(computeSha256Hex(der), normalizedPin)) {
        continue;
      }
      buffer.write(encodeDerCertificateAsPem(Uint8List.fromList(der)));
    }
    return buffer.toString();
  }

  /// ADR-017: Güvenilen kök CA bağlamındaki BoringSSL doğrulama hatasını sınıflandırır.
  ///
  /// Yalnızca açıkça tanınan SAN/IP, hostname ve süre hataları
  /// [TlsCertificateFailureKind] olarak döner; güven zinciri, kendi imzalı veya
  /// bilinmeyen hatalar fail-closed biçimde `null` döner (`TlsPinMismatchException`).
  static TlsCertificateFailureKind? classifyCaTrustedCertError(
    HandshakeException error,
  ) {
    final msg = '${error.osError?.message ?? ''} ${error.message}'.toLowerCase();
    if (msg.contains('ip address mismatch')) {
      return TlsCertificateFailureKind.ipAddressMismatch;
    }
    if (msg.contains('hostname mismatch') || msg.contains('name mismatch')) {
      return TlsCertificateFailureKind.hostnameMismatch;
    }
    if (msg.contains('certificate has expired') || msg.contains('cert_has_expired')) {
      return TlsCertificateFailureKind.certificateExpired;
    }
    if (msg.contains('not yet valid') || msg.contains('cert_not_yet_valid')) {
      return TlsCertificateFailureKind.certificateNotYetValid;
    }
    return null;
  }

  /// Verilen [PinnedTlsConfig] için CA-pin modunun aktif olup olmadığını döner.
  static bool isCaPinnedConfig(PinnedTlsConfig config) {
    final normalizedPin = config.normalizedExpectedSha256;
    if (normalizedPin.length != 64 ||
        !RegExp(r'^[0-9A-F]{64}$').hasMatch(normalizedPin)) {
      return false;
    }
    final rawPem = config.caCertPem?.trim();
    if (rawPem == null || rawPem.isEmpty) return false;
    final pemCerts = extractPemCertificatesDer(rawPem);
    return pemCerts
        .map(computeSha256Hex)
        .any((h) => _constantTimeEquals(h, normalizedPin));
  }

  static HttpClient createHttpClient(PinnedTlsConfig config) =>
      _createHttpClient(config, null);

  static HttpClient _createHttpClient(
    PinnedTlsConfig config,
    _PinRejectionLog? rejections,
  ) {
    final normalizedPin = config.normalizedExpectedSha256;
    if (normalizedPin.length != 64 ||
        !RegExp(r'^[0-9A-F]{64}$').hasMatch(normalizedPin)) {
      throw const FormatException(
        'Geçersiz SHA-256 sertifika parmak izi (64 hex karakter beklenir).',
      );
    }

    final rawPem = config.caCertPem?.trim();
    if (rawPem != null && rawPem.isNotEmpty) {
      final pemCerts = extractPemCertificatesDer(rawPem);
      final caHashes = pemCerts.map(computeSha256Hex).toList(growable: false);
      final expectedMatchesCaPem =
          caHashes.any((h) => _constantTimeEquals(h, normalizedPin));

      // Yalnızca sabitlenen parmak iziyle eşleşen CA sertifikasını izole güven
      // bağlamına yükle (CA-bundle sızması önlenir). Bu modda badCertificateCallback
      // hiçbir zaman true dönmez; yalnızca tanılama/sınıflandırma için yaprak
      // parmak izini kaydeder.
      if (expectedMatchesCaPem) {
        final matchedCaPem = _encodeMatchedCertificatesAsPem(pemCerts, normalizedPin);
        final context = SecurityContext(withTrustedRoots: false);
        context.setTrustedCertificatesBytes(utf8.encode(matchedCaPem));
        final client = HttpClient(context: context);
        client.badCertificateCallback = (cert, host, port) {
          final presentedHex = computeSha256Hex(cert.der);
          rejections?.record(
            host,
            port,
            presentedHex,
            isCaPinnedMode: true,
          );
          return false;
        };
        return client;
      }
    }

    // Doğrudan yaprak pin modu (CA PEM yoksa veya pin CA ile eşleşmiyorsa):
    // Sunulan yaprak sertifikanın SHA-256 parmak izi sabit zamanlı doğrulanır.
    final emptyContext = SecurityContext(withTrustedRoots: false);
    final client = HttpClient(context: emptyContext);
    client.badCertificateCallback = (cert, host, port) {
      final presentedHex = computeSha256Hex(cert.der);
      final accepted = _constantTimeEquals(presentedHex, normalizedPin);
      if (!accepted) {
        rejections?.record(
          host,
          port,
          presentedHex,
          isCaPinnedMode: false,
        );
      }
      return accepted;
    };
    return client;
  }

  /// Faz 7B: Pin uyuşmazlığında [TlsPinMismatchException], güvenilen CA altındaki
  /// SAN/hostname/tarih hatalarında [TlsCertificateValidationException] fırlatan istemci.
  static http.Client createClient(PinnedTlsConfig config) {
    final rejections = _PinRejectionLog();
    final caPinnedMode = isCaPinnedConfig(config);
    return _PinAwareClient(
      IOClient(_createHttpClient(config, rejections)),
      rejections,
      caPinnedMode,
    );
  }

  /// P-BLOCK-1 / P-BLOCK-2: Yalnzca Katman 1 + Katman 2 (`MmsX509PreValidator`)
  /// doğrulamasından geçmiş Root CA ile salt-CA sabitli TLS istemcisi kurar.
  /// `badCertificateCallback` ASLA `true` dönmez; yaprak-pin fallback yapılmaz.
  static http.Client createStrictCaPinnedClient({
    required Uint8List caCertBytes,
    required String expectedCaSha256Hex,
    DateTime? nowUtc,
  }) {
    final normalizedPin = PinnedTlsConfig.normalizeHex(expectedCaSha256Hex);
    if (normalizedPin.length != 64 ||
        !RegExp(r'^[0-9A-F]{64}$').hasMatch(normalizedPin)) {
      throw const FormatException(
        'Geçersiz Root CA SHA-256 parmak izi (64 hex karakter beklenir).',
      );
    }
    final canonical = validateAndComputeCaPin(caCertBytes, nowUtc: nowUtc);
    if (!constantTimeEqualsAscii(canonical.sha256Hex, normalizedPin)) {
      throw TlsPinMismatchException(
        host: 'ca-pin',
        port: 0,
        presentedSha256: canonical.sha256Hex,
        reason: TlsPinMismatchReason.untrustedCaChain,
      );
    }
    final context = SecurityContext(withTrustedRoots: false);
    context.setTrustedCertificatesBytes(canonical.toPemBytes());
    final rejections = _PinRejectionLog();
    final client = HttpClient(context: context);
    client.badCertificateCallback = (cert, host, port) {
      rejections.record(
        host,
        port,
        computeSha256Hex(cert.der),
        isCaPinnedMode: true,
      );
      return false;
    };
    return _PinAwareClient(
      IOClient(client),
      rejections,
      true,
    );
  }
}

class _PinRejection {
  final String presentedSha256;
  final bool isCaPinnedMode;

  const _PinRejection({
    required this.presentedSha256,
    required this.isCaPinnedMode,
  });
}

/// badCertificateCallback içinde reddedilen sunucu parmak izlerinin endpoint başına
/// FIFO kuyruğu (aynı host:port paralel isteklerinde kayıt kaybı/ezilmesini önler).
class _PinRejectionLog {
  static const int _maxQueuedPerEndpoint = 64;

  final Map<String, List<_PinRejection>> _queues = {};
  final Map<String, int> _inFlight = {};

  void beginRequest(String host, int port) {
    final key = '$host:$port';
    final current = _inFlight[key] ?? 0;
    if (current == 0) {
      _queues.remove(key);
    }
    _inFlight[key] = current + 1;
  }

  void record(
    String host,
    int port,
    String presentedSha256, {
    required bool isCaPinnedMode,
  }) {
    final key = '$host:$port';
    final queue = _queues.putIfAbsent(key, () => <_PinRejection>[]);
    if (queue.length >= _maxQueuedPerEndpoint) {
      queue.removeAt(0);
    }
    queue.add(
      _PinRejection(
        presentedSha256: presentedSha256,
        isCaPinnedMode: isCaPinnedMode,
      ),
    );
  }

  _PinRejection? take(String host, int port) {
    final key = '$host:$port';
    final queue = _queues[key];
    if (queue == null || queue.isEmpty) return null;
    final popped = queue.removeAt(0);
    if (queue.isEmpty) {
      _queues.remove(key);
    }
    return popped;
  }

  void endRequest(String host, int port) {
    final key = '$host:$port';
    final next = (_inFlight[key] ?? 1) - 1;
    if (next <= 0) {
      _inFlight.remove(key);
      _queues.remove(key);
    } else {
      _inFlight[key] = next;
    }
  }
}

class _PinAwareClient extends http.BaseClient {
  final http.Client _inner;
  final _PinRejectionLog _rejections;
  final bool _isCaPinnedMode;

  _PinAwareClient(
    this._inner,
    this._rejections,
    this._isCaPinnedMode,
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final host = request.url.host;
    final port = request.url.port;
    _rejections.beginRequest(host, port);
    try {
      return await _inner.send(request);
    } on HandshakeException catch (e) {
      final rejection = _rejections.take(host, port);
      if (rejection != null) {
        if (rejection.isCaPinnedMode) {
          final certFailure =
              MmsPinnedTlsClientFactory.classifyCaTrustedCertError(e);
          if (certFailure != null) {
            throw TlsCertificateValidationException(
              kind: certFailure,
              host: host,
              port: port,
              presentedSha256: rejection.presentedSha256,
              detail: e.osError?.message ?? e.message,
            );
          }
          throw TlsPinMismatchException(
            host: host,
            port: port,
            presentedSha256: rejection.presentedSha256,
            reason: TlsPinMismatchReason.untrustedCaChain,
          );
        }
        throw TlsPinMismatchException(
          host: host,
          port: port,
          presentedSha256: rejection.presentedSha256,
          reason: TlsPinMismatchReason.leafPinMismatch,
        );
      }

      // Paralel iptal/soket yarışında rejection sırası düşmüşse veya CA öz-sunumunda
      // BoringSSL callback öncesi KEY_USAGE_BIT_INCORRECT fırlatmışsa sertifika
      // hatası ham HandshakeException olarak sızdırılmaz (fail-closed).
      final msg = '${e.osError?.message ?? ''} ${e.message}'.toLowerCase();
      if (_isCaPinnedMode &&
          (msg.contains('certificate_verify_failed') ||
              msg.contains('key_usage'))) {
        final certFailure =
            MmsPinnedTlsClientFactory.classifyCaTrustedCertError(e);
        if (certFailure != null) {
          throw TlsCertificateValidationException(
            kind: certFailure,
            host: host,
            port: port,
            detail: e.osError?.message ?? e.message,
          );
        }
        throw TlsPinMismatchException(
          host: host,
          port: port,
          presentedSha256: 'UNKNOWN',
          reason: TlsPinMismatchReason.untrustedCaChain,
        );
      }
      rethrow;
    } finally {
      _rejections.endRequest(host, port);
    }
  }

  @override
  void close() => _inner.close();
}
