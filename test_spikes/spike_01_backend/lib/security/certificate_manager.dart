import 'dart:io';
import 'dart:typed_data';
import 'package:mms_client_storage/mms_client_storage.dart';

class TlsConfigurationException implements Exception {
  final String message;
  TlsConfigurationException(this.message);

  @override
  String toString() => 'TlsConfigurationException: $message';
}

class TlsSecurityException implements Exception {
  final String message;
  TlsSecurityException(this.message);

  @override
  String toString() => 'TlsSecurityException: $message';
}

/// Windows Local Master Hub ve istemciler için Kök CA, sunucu sertifikaları
/// ve TLS SecurityContext yönetimini sağlayan servis.
class CertificateManager {
  static String? _cachedOpenSslPath;

  /// Sistemde veya Git kurulumundaki OpenSSL yürütülebilir dosyasını tespit eder.
  static String getOpenSslPath() {
    if (_cachedOpenSslPath != null) return _cachedOpenSslPath!;

    final envPath = Platform.environment['OPENSSL_PATH'];
    if (envPath != null && File(envPath).existsSync()) {
      _cachedOpenSslPath = envPath;
      return envPath;
    }

    // 1. Git for Windows OpenSSL (OpenSSL 3.x)
    const gitOpenSsl = r'C:\Program Files\Git\usr\bin\openssl.exe';
    if (File(gitOpenSsl).existsSync()) {
      _cachedOpenSslPath = gitOpenSsl;
      return gitOpenSsl;
    }

    // 2. Sistem genelindeki OpenSSL
    try {
      final res = Process.runSync('where.exe', ['openssl']);
      if (res.exitCode == 0) {
        final path = res.stdout.toString().split('\r\n').first.trim();
        if (File(path).existsSync()) {
          _cachedOpenSslPath = path;
          return path;
        }
      }
    } catch (_) {}

    // Fallback: doğrudan 'openssl'
    _cachedOpenSslPath = 'openssl';
    return 'openssl';
  }

  /// 10 yıllık, self-signed yerel Kök Sertifika Otoritesi (Root CA) üretir.
  /// P-BLOCK-1 (`DEC-REV-1`): Zorunlu X.509v3 `basicConstraints=critical,CA:TRUE`
  /// ve `keyUsage=critical,keyCertSign,cRLSign` eklentileri ile üretilir.
  static void generateRootCa({
    required String caKeyPath,
    required String caCertPath,
    String commonName = 'Market MMS Local Root CA',
    int validityDays = 3650,
  }) {
    final openssl = getOpenSslPath();
    final res = Process.runSync(openssl, [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      caKeyPath,
      '-out',
      caCertPath,
      '-days',
      validityDays.toString(),
      '-subj',
      '/CN=$commonName',
      '-addext',
      'basicConstraints=critical,CA:TRUE',
      '-addext',
      'keyUsage=critical,keyCertSign,cRLSign',
    ]);

    if (res.exitCode != 0 || !File(caCertPath).existsSync()) {
      throw TlsConfigurationException('Root CA üretilemedi: ${res.stderr}');
    }
  }

  /// Root CA tarafından imzalanmış 1 yıllık yaprak sunucu TLS sertifikası üretir.
  static void generateServerCertificate({
    required String caKeyPath,
    required String caCertPath,
    required String serverKeyPath,
    required String serverCertPath,
    String commonName = 'localhost',
    List<String> sanList = const ['localhost', '127.0.0.1'],
    int validityDays = 365,
  }) {
    final openssl = getOpenSslPath();
    final tempDir = Directory.systemTemp.createTempSync('mms_csr_');
    final csrPath = '${tempDir.path}\\server.csr';

    final sanFormatted = sanList.map((entry) {
      if (entry.contains('.') && RegExp(r'^[0-9.]+$').hasMatch(entry)) {
        return 'IP:$entry';
      }
      return 'DNS:$entry';
    }).join(',');

    try {
      // 1. Özel anahtar ve CSR oluştur
      final csrRes = Process.runSync(openssl, [
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        serverKeyPath,
        '-out',
        csrPath,
        '-subj',
        '/CN=$commonName',
        '-addext',
        'subjectAltName=$sanFormatted',
      ]);

      if (csrRes.exitCode != 0 || !File(serverKeyPath).existsSync()) {
        throw TlsConfigurationException('Sunucu CSR oluşturulamadı: ${csrRes.stderr}');
      }

      // 2. Root CA ile imzala
      final signRes = Process.runSync(openssl, [
        'x509',
        '-req',
        '-in',
        csrPath,
        '-CA',
        caCertPath,
        '-CAkey',
        caKeyPath,
        '-CAcreateserial',
        '-out',
        serverCertPath,
        '-days',
        validityDays.toString(),
        '-copy_extensions',
        'copy',
      ]);

      if (signRes.exitCode != 0 || !File(serverCertPath).existsSync()) {
        throw TlsConfigurationException('Sunucu sertifikası imzalanamadı: ${signRes.stderr}');
      }
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  }

  /// Negatif test senaryoları için süresi geçmiş (expired) sunucu sertifikası üretir.
  static void generateExpiredServerCertificate({
    required String caKeyPath,
    required String caCertPath,
    required String serverKeyPath,
    required String serverCertPath,
    String commonName = 'localhost',
  }) {
    final openssl = getOpenSslPath();
    final tempDir = Directory.systemTemp.createTempSync('mms_exp_csr_');
    final csrPath = '${tempDir.path}\\server_exp.csr';

    try {
      final csrRes = Process.runSync(openssl, [
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        serverKeyPath,
        '-out',
        csrPath,
        '-subj',
        '/CN=$commonName',
      ]);

      if (csrRes.exitCode != 0) {
        throw TlsConfigurationException('CSR oluşturulamadı: ${csrRes.stderr}');
      }

      // Geçmişte süresi bitmiş sertifika imzala (OpenSSL 3.x uyumlu)
      final signRes = Process.runSync(openssl, [
        'x509',
        '-req',
        '-in',
        csrPath,
        '-CA',
        caCertPath,
        '-CAkey',
        caKeyPath,
        '-CAcreateserial',
        '-out',
        serverCertPath,
        '-not_before',
        '20200101000000Z',
        '-not_after',
        '20200102000000Z',
      ]);

      if (signRes.exitCode != 0) {
        throw TlsConfigurationException('Süresi dolmuş sertifika imzalanamadı: ${signRes.stderr}');
      }
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  }

  /// İki nokta ayraçlı SHA-256 hex gösterimi üretir (örn: 4F:A2:8B:...).
  static String formatSha256Colon(String normalizedHex) {
    final clean = normalizedHex.replaceAll(':', '').replaceAll(' ', '').trim().toUpperCase();
    final buffer = StringBuffer();
    for (var i = 0; i < clean.length; i += 2) {
      if (i > 0) buffer.write(':');
      buffer.write(clean.substring(i, i + 2 <= clean.length ? i + 2 : clean.length));
    }
    return buffer.toString();
  }

  /// Sertifikanın kanonik tekil DER SHA-256 özetini (fingerprint) hesaplar (örn: 4F:A2:8B:...).
  ///
  /// P-BLOCK-1 (`DEC-REV-1`): PEM veya ham DER girdisinden tekil kanonik DER
  /// gövdesi çıkarılır ve yalnızca DER baytları üzerinden özet alınır.
  static String computeSha256Fingerprint(List<int> certBytes) {
    final canonical = extractCanonicalSingleCertDer(
      Uint8List.fromList(certBytes),
    );
    return formatSha256Colon(canonical.sha256Hex);
  }

  /// Root CA dosyasını Katman 1 + Katman 2 (`MmsX509PreValidator`) kurallarıyla doğrular
  /// ve kanonik tekil DER + iki nokta ayraçlı parmak izi bilgisini döner.
  static ({CanonicalCertDerResult canonical, String colonFingerprint}) validateRootCaBytes(
    List<int> certBytes, {
    DateTime? nowUtc,
  }) {
    final canonical = extractCanonicalSingleCertDer(
      Uint8List.fromList(certBytes),
    );
    MmsX509PreValidator.validateRootCaDer(canonical.derBytes, nowUtc: nowUtc);
    return (
      canonical: canonical,
      colonFingerprint: formatSha256Colon(canonical.sha256Hex),
    );
  }

  /// Sunucu sertifikası (`server.crt`) içindeki IPv4 SAN (`iPAddress [7]`) kümesini çıkarır.
  static Set<String> extractServerCertSanIpv4s(List<int> serverCertBytes) {
    final canonical = extractCanonicalSingleCertDer(
      Uint8List.fromList(serverCertBytes),
      invalidCode: 'INVALID_SERVER_CERT',
    );
    return MmsX509PreValidator.extractServerSanIpv4s(canonical.derBytes);
  }

  /// Sunucu için doğrulanmış, güvenli SecurityContext oluşturur.
  static SecurityContext createServerSecurityContext({
    required String certChainPath,
    required String privateKeyPath,
    String? password,
  }) {
    final certFile = File(certChainPath);
    final keyFile = File(privateKeyPath);

    if (!certFile.existsSync()) {
      throw TlsConfigurationException('Sertifika dosyası bulunamadı: $certChainPath');
    }
    if (!keyFile.existsSync()) {
      throw TlsConfigurationException('Özel anahtar dosyası bulunamadı: $privateKeyPath');
    }
    if (certFile.lengthSync() == 0 || keyFile.lengthSync() == 0) {
      throw TlsConfigurationException('Sertifika veya özel anahtar dosyası boş.');
    }

    try {
      final context = SecurityContext();
      context.useCertificateChain(certChainPath);
      context.usePrivateKey(privateKeyPath, password: password);
      return context;
    } catch (e) {
      throw TlsConfigurationException('TLS SecurityContext yüklenemedi: $e');
    }
  }
}

