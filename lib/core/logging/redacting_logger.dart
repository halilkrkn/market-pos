import 'dart:collection';

import '../utils/user_friendly_error_mapper.dart';

enum RedactedLogLevel { info, warning, error }

class RedactedLogEntry {
  final DateTime timestamp;
  final RedactedLogLevel level;
  final String category;
  final String message;

  const RedactedLogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestamp': timestamp.toUtc().toIso8601String(),
        'level': level.name,
        'category': category,
        'message': message,
      };
}

/// Parola, Bearer token, pairing secret ve özel anahtar sızıntılarını otomatik
/// maskeleyen dairesel tamponlu günlükleyici.
class RedactingLogger {
  final int maxEntries;
  final ListQueue<RedactedLogEntry> _entries = ListQueue<RedactedLogEntry>();
  final List<String> _registeredSecrets = <String>[];

  RedactingLogger({this.maxEntries = 200});

  void registerSensitiveValue(String? secret) {
    if (secret == null) return;
    final trimmed = secret.trim();
    if (trimmed.length < 4) return;
    if (!_registeredSecrets.contains(trimmed)) {
      _registeredSecrets.add(trimmed);
    }
  }

  String redact(String raw) {
    var sanitized = raw;

    // PEM private key bloklarını temizle
    sanitized = sanitized.replaceAll(
      RegExp(
        r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
      ),
      '[REDACTED_PRIVATE_KEY]',
    );

    // JSON veya sorgu dizgisindeki hassas alanları maskele
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'("(?:auth_code|code|pairing_secret|device_token|access_token|accessToken|refresh_token|refreshToken|token|password|backupPassword|backup_password|recovery_password|recoveryPassword|privateKey|private_key|client_secret|clientSecret|admin_secret|adminSecret|live_sync_secret|dpapi_secret|signing_key|code_verifier|x-mms-admin-secret|x-admin-secret|api_key|upload_id|session|signature|sig|secret|pepper)"\s*:\s*)"[^"]*"',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}"[REDACTED]"',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r"""\b(auth_code|code|pairing_secret|device_token|access_token|refresh_token|recovery_password|client_secret|admin_secret|live_sync_secret|dpapi_secret|signing_key|code_verifier|x-mms-admin-secret|x-admin-secret|api_key|key|upload_id|session|signature|sig|password|secret|pepper|token)=([^&#\s,"'`\)\]]+)""",
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}=[REDACTED]',
    );

    for (final secret in _registeredSecrets) {
      if (secret.isNotEmpty) {
        sanitized = sanitized.replaceAll(secret, '[REDACTED]');
      }
    }
    return UserFriendlyErrorMapper.redactSecrets(sanitized);
  }

  void log(
    RedactedLogLevel level,
    String category,
    String message, {
    DateTime? timestamp,
  }) {
    final entry = RedactedLogEntry(
      timestamp: (timestamp ?? DateTime.now()).toUtc(),
      level: level,
      category: category,
      message: redact(message),
    );
    if (_entries.length >= maxEntries) {
      _entries.removeFirst();
    }
    _entries.addLast(entry);
  }

  void info(String category, String message) =>
      log(RedactedLogLevel.info, category, message);

  void warning(String category, String message) =>
      log(RedactedLogLevel.warning, category, message);

  void error(String category, String message) =>
      log(RedactedLogLevel.error, category, message);

  List<RedactedLogEntry> get entries => List<RedactedLogEntry>.unmodifiable(_entries);

  void clear() => _entries.clear();
}
