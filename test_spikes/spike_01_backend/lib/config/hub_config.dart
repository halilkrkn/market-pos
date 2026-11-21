import 'dart:convert';
import 'dart:io';

import 'package:mms_client_storage/mms_client_storage.dart'
    show BackupSchedulePolicy, RetentionPolicy;
import 'package:path/path.dart' as p;

class HubConfigException implements Exception {
  final String message;
  const HubConfigException(this.message);

  @override
  String toString() => 'HubConfigException: $message';
}

/// REL-01: Windows Master Hub için TEK doğrulanmış yapılandırma kaynağı.
///
/// `%ProgramData%\MarketMMS\config\hub_config.json` dosyasından okunur; WinSW
/// servisi yalnızca `--config=<yol>` argümanı geçirir. Göreli yollar config
/// dosyasının bulunduğu dizine göre çözülür. Sırlar (admin secret, pepper,
/// özel anahtar) dosyada düz metin olarak tutulmaz; yalnızca ACL korumalı
/// dosya yolları referans verilir.
class HubConfig {
  final String environment;
  final int port;
  final int discoveryPort;
  final bool enableDiscovery;
  final String dbPath;
  final String? backupDir;
  final String? pepperPath;
  final String? adminSecretFile;
  final bool enableTls;
  final String? certPath;
  final String? keyPath;

  /// PAIR-CA: Eşleştirme QR'ındaki CA parmak izi ve `/api/v1/pairing/ca-cert` için kök CA
  /// sertifikası (yalnızca GENEL sertifika; `ca.key` Hub diskinde bulunmaz). Üretimde zorunlu.
  final String? caCertPath;
  final String tenantId;
  final String storeId;
  final String hubId;
  final bool requireTenantStoreHeaders;

  /// Faz 3: Zamanlanmış şifreli Hub yedeği (varsayılan 24 saat; 0 → kapalı).
  final BackupSchedulePolicy backupSchedule;

  const HubConfig({
    required this.environment,
    required this.port,
    required this.discoveryPort,
    required this.enableDiscovery,
    required this.dbPath,
    required this.backupDir,
    required this.pepperPath,
    required this.adminSecretFile,
    required this.enableTls,
    required this.certPath,
    required this.keyPath,
    this.caCertPath,
    required this.tenantId,
    required this.storeId,
    required this.hubId,
    required this.requireTenantStoreHeaders,
    this.backupSchedule = defaultBackupSchedule,
  });

  static const BackupSchedulePolicy defaultBackupSchedule =
      BackupSchedulePolicy(interval: Duration(hours: 24));

  static const Set<String> _allowedBackupScheduleKeys = {
    'interval_hours',
    'daily_retention_days',
    'monthly_retention_months',
  };

  static const Set<String> _allowedTlsKeys = {
    'enabled',
    'cert',
    'key',
    'ca_cert',
  };

  bool get isProduction => environment == 'production';

  static const Set<String> _allowedKeys = {
    'environment',
    'port',
    'discovery_port',
    'enable_discovery',
    'db_path',
    'backup_dir',
    'pepper_file',
    'admin_secret_file',
    'tls',
    'tenant_id',
    'store_id',
    'hub_id',
    'require_tenant_store_headers',
    'backup_schedule',
  };

  static HubConfig load(File file) {
    if (!file.existsSync()) {
      throw HubConfigException('Yapılandırma dosyası bulunamadı: ${file.path}');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      throw HubConfigException('Yapılandırma dosyası geçerli JSON değil: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const HubConfigException('Yapılandırma kökü bir JSON nesnesi olmalıdır.');
    }
    return fromJson(decoded, baseDir: file.parent.path);
  }

  static HubConfig fromJson(Map<String, dynamic> json, {required String baseDir}) {
    if (json.containsKey('admin_secret')) {
      throw const HubConfigException(
        'admin_secret düz metin olarak yapılandırmada tutulamaz; admin_secret_file (ACL korumalı) kullanın.',
      );
    }
    final unknown = json.keys.where((k) => !_allowedKeys.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw HubConfigException('Bilinmeyen yapılandırma anahtar(lar)ı: ${unknown.join(', ')}');
    }

    String? resolve(Object? raw) {
      if (raw == null) return null;
      if (raw is! String || raw.trim().isEmpty) {
        throw HubConfigException('Dosya yolu boş olmayan metin olmalıdır: $raw');
      }
      return p.normalize(p.isAbsolute(raw) ? raw : p.join(baseDir, raw));
    }

    int readPort(String key, int fallback) {
      final raw = json[key] ?? fallback;
      if (raw is! int || raw < 1 || raw > 65535) {
        throw HubConfigException('$key 1-65535 arasında bir tamsayı olmalıdır: $raw');
      }
      return raw;
    }

    String readId(String key, String fallback) {
      final raw = json[key] ?? fallback;
      if (raw is! String || raw.trim().isEmpty) {
        throw HubConfigException('$key boş olamaz.');
      }
      return raw.trim();
    }

    bool readBool(Map<String, dynamic> source, String key, bool fallback) {
      final raw = source[key] ?? fallback;
      if (raw is! bool) throw HubConfigException('$key true/false olmalıdır.');
      return raw;
    }

    final environment = readId('environment', 'production');
    if (environment != 'production' && environment != 'development') {
      throw HubConfigException('environment "production" veya "development" olmalıdır: $environment');
    }
    final port = readPort('port', 8945);
    final discoveryPort = readPort('discovery_port', 8946);
    if (port == discoveryPort) {
      throw const HubConfigException('port ve discovery_port aynı olamaz.');
    }

    final tlsRaw = json['tls'] ?? const <String, dynamic>{};
    if (tlsRaw is! Map) throw const HubConfigException('tls bir nesne olmalıdır.');
    final tls = Map<String, dynamic>.from(tlsRaw);
    final unknownTls = tls.keys.where((k) => !_allowedTlsKeys.contains(k)).toList();
    if (unknownTls.isNotEmpty) {
      throw HubConfigException('Bilinmeyen tls anahtar(lar)ı: ${unknownTls.join(', ')}');
    }
    final enableTls = readBool(tls, 'enabled', false);
    final certPath = resolve(tls['cert']);
    final keyPath = resolve(tls['key']);
    final caCertPath = resolve(tls['ca_cert']);
    if (caCertPath != null && !File(caCertPath).existsSync()) {
      throw HubConfigException('tls.ca_cert dosyası bulunamadı: $caCertPath');
    }
    if (enableTls) {
      for (final entry in {'cert': certPath, 'key': keyPath}.entries) {
        if (entry.value == null || !File(entry.value!).existsSync()) {
          throw HubConfigException('TLS etkin ancak tls.${entry.key} dosyası bulunamadı: ${entry.value}');
        }
      }
    }

    final requireHeaders = readBool(json, 'require_tenant_store_headers', true);
    if (environment == 'production') {
      if (!enableTls) {
        throw const HubConfigException('Üretim ortamında TLS zorunludur (tls.enabled=true).');
      }
      if (!requireHeaders) {
        throw const HubConfigException('Üretim ortamında tenant/store başlık zorunluluğu kapatılamaz.');
      }
      if (caCertPath == null) {
        throw const HubConfigException(
          'Üretim ortamında tls.ca_cert (eşleştirme kök CA sertifikası) zorunludur; '
          'aksi halde cihazlar QR ile eşleştirilirken TLS pin kurulamaz.',
        );
      }
    }

    final dbPath = resolve(json['db_path'] ?? 'data/market_master.db')!;

    final scheduleRaw = json['backup_schedule'] ?? const <String, dynamic>{};
    if (scheduleRaw is! Map) throw const HubConfigException('backup_schedule bir nesne olmalıdır.');
    final schedule = Map<String, dynamic>.from(scheduleRaw);
    final unknownSchedule = schedule.keys.where((k) => !_allowedBackupScheduleKeys.contains(k)).toList();
    if (unknownSchedule.isNotEmpty) {
      throw HubConfigException('Bilinmeyen backup_schedule anahtar(lar)ı: ${unknownSchedule.join(', ')}');
    }
    int readRange(String key, int fallback, int min, int max) {
      final raw = schedule[key] ?? fallback;
      if (raw is! int || raw < min || raw > max) {
        throw HubConfigException('backup_schedule.$key $min-$max arasında tamsayı olmalıdır: $raw');
      }
      return raw;
    }

    final backupSchedule = BackupSchedulePolicy(
      interval: Duration(hours: readRange('interval_hours', 24, 0, 168)),
      retention: RetentionPolicy(
        dailyRetentionDays: readRange('daily_retention_days', 30, 1, 3650),
        monthlyRetentionMonths: readRange('monthly_retention_months', 12, 0, 120),
      ),
    );

    return HubConfig(
      environment: environment,
      port: port,
      discoveryPort: discoveryPort,
      enableDiscovery: readBool(json, 'enable_discovery', true),
      dbPath: dbPath,
      backupDir: resolve(json['backup_dir']) ?? p.normalize(p.join(baseDir, 'backups')),
      pepperPath: resolve(json['pepper_file']),
      adminSecretFile: resolve(json['admin_secret_file']),
      enableTls: enableTls,
      certPath: certPath,
      keyPath: keyPath,
      caCertPath: caCertPath,
      tenantId: readId('tenant_id', 'default-tenant'),
      storeId: readId('store_id', 'default-store'),
      hubId: readId('hub_id', 'MMS-HUB-MASTER'),
      requireTenantStoreHeaders: requireHeaders,
      backupSchedule: backupSchedule,
    );
  }

  /// Admin secret'ı ACL korumalı dosyadan okur; dosya yoksa/boşsa `null` (admin uçları fail-closed 503).
  String? readAdminSecret() {
    final path = adminSecretFile;
    if (path == null) return null;
    final f = File(path);
    if (!f.existsSync()) return null;
    final value = f.readAsStringSync().trim();
    return value.isEmpty ? null : value;
  }
}
