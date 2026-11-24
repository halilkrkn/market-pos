import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../security/dpapi.dart';

class HubBackupOAuthException implements Exception {
  final String code;
  final String message;

  const HubBackupOAuthException(this.code, this.message);

  @override
  String toString() => 'HubBackupOAuthException [$code]: $message';
}

/// Hub merkezi yedekleme OAuth kasasında DPAPI + pOptionalEntropy ile korunan kimlik bilgileri.
/// Canlı sync gizlisi (`live_drive_sync_secret.dpapi`) ile kesinlikle karışmaz (`OV-02`).
class HubBackupOAuthCredentials {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAtUtc;
  final String? accountEmail;
  final String scope;
  final String? folderId;

  /// S5: [folderId] hangi klasör düzenine ait? Yalnızca [hubSubfolderLayout] ise
  /// yükleyici önbellek olarak kullanır; aksi halde (ör. eski kök klasör kimliği)
  /// `MARKET MMS Yedekleri/Hub` yeniden çözülür. Gizli bilgi değildir.
  final String? folderLayout;
  final DateTime connectedAtUtc;
  final bool needsReauth;
  final String? lastErrorCode;

  static const String hubSubfolderLayout = 'HUB_SUBFOLDER_V1';

  const HubBackupOAuthCredentials({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAtUtc,
    this.accountEmail,
    required this.scope,
    this.folderId,
    this.folderLayout,
    required this.connectedAtUtc,
    this.needsReauth = false,
    this.lastErrorCode,
  });

  HubBackupOAuthCredentials copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAtUtc,
    String? accountEmail,
    String? scope,
    String? folderId,
    String? folderLayout,
    DateTime? connectedAtUtc,
    bool? needsReauth,
    String? lastErrorCode,
    bool clearLastError = false,
  }) =>
      HubBackupOAuthCredentials(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        expiresAtUtc: expiresAtUtc ?? this.expiresAtUtc,
        accountEmail: accountEmail ?? this.accountEmail,
        scope: scope ?? this.scope,
        folderId: folderId ?? this.folderId,
        folderLayout: folderLayout ?? this.folderLayout,
        connectedAtUtc: connectedAtUtc ?? this.connectedAtUtc,
        needsReauth: needsReauth ?? this.needsReauth,
        lastErrorCode: clearLastError ? null : (lastErrorCode ?? this.lastErrorCode),
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at_utc': expiresAtUtc.toUtc().toIso8601String(),
        'account_email': accountEmail,
        'scope': scope,
        'folder_id': folderId,
        'folder_layout': folderLayout,
        'connected_at_utc': connectedAtUtc.toUtc().toIso8601String(),
        'needs_reauth': needsReauth,
        'last_error_code': lastErrorCode,
      };

  factory HubBackupOAuthCredentials.fromJson(Map<String, dynamic> json) {
    final access = (json['access_token'] as String?) ?? '';
    final refresh = (json['refresh_token'] as String?) ?? '';
    if (refresh.isEmpty) {
      throw const HubBackupOAuthException(
        'ERR_OAUTH_CORRUPT_STORE',
        'Kayıtlı Hub OAuth verisinde refresh_token eksik.',
      );
    }
    return HubBackupOAuthCredentials(
      accessToken: access,
      refreshToken: refresh,
      expiresAtUtc: DateTime.parse(json['expires_at_utc'] as String).toUtc(),
      accountEmail: json['account_email'] as String?,
      scope: (json['scope'] as String?) ?? '',
      folderId: json['folder_id'] as String?,
      folderLayout: json['folder_layout'] as String?,
      connectedAtUtc: DateTime.parse(json['connected_at_utc'] as String).toUtc(),
      needsReauth: (json['needs_reauth'] as bool?) ?? false,
      lastErrorCode: json['last_error_code'] as String?,
    );
  }
}

/// DPAPI + entropy soyutlaması (gerçek ortamda [WindowsDpapiEntropyCipher]).
abstract class HubSecretCipher {
  Uint8List protect(List<int> plainBytes, List<int> entropy);
  Uint8List unprotect(List<int> cipherBytes, List<int> entropy);
}

class WindowsDpapiEntropyCipher implements HubSecretCipher {
  const WindowsDpapiEntropyCipher();

  @override
  Uint8List protect(List<int> plainBytes, List<int> entropy) =>
      WindowsDpapi.protect(plainBytes, entropy: entropy);

  @override
  Uint8List unprotect(List<int> cipherBytes, List<int> entropy) =>
      WindowsDpapi.unprotect(cipherBytes, entropy: entropy);
}

/// `OV-01` & `OV-02`: Hub Google Drive Backup OAuth kasası (`backup_drive_oauth.dpapi`).
/// `LocalMachine` DPAPI + alan-ayrımlı `pOptionalEntropy` ile şifrelenir; `live_drive_sync_secret.dpapi`
/// dosyasından tamamen bağımsızdır ve Windows UI tarafından doğrudan okunamaz.
class HubBackupOAuthStore {
  static const String defaultFileName = 'backup_drive_oauth.dpapi';
  static final List<int> backupOAuthEntropy =
      utf8.encode('MarketMMS:HubBackupDriveOAuth:v1');

  final File file;
  final HubSecretCipher cipher;

  HubBackupOAuthStore(
    this.file, {
    HubSecretCipher? cipher,
  }) : cipher = cipher ?? const WindowsDpapiEntropyCipher();

  Future<void> save(HubBackupOAuthCredentials credentials) async {
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final plainBytes = utf8.encode(jsonEncode(credentials.toJson()));
    final encrypted = cipher.protect(plainBytes, backupOAuthEntropy);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(encrypted, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  Future<HubBackupOAuthCredentials?> load() async {
    if (!await file.exists()) return null;
    final encrypted = await file.readAsBytes();
    if (encrypted.isEmpty) {
      throw const HubBackupOAuthException(
        'ERR_OAUTH_CORRUPT_STORE',
        'Hub Drive OAuth kasa dosyası boş veya bozuk.',
      );
    }
    final Uint8List decrypted;
    try {
      decrypted = cipher.unprotect(encrypted, backupOAuthEntropy);
    } catch (e) {
      throw HubBackupOAuthException(
        'ERR_OAUTH_DPAPI_UNPROTECT',
        'Hub Drive OAuth kasası DPAPI/entropy ile çözülemedi: $e',
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(decrypted));
      if (decoded is! Map) {
        throw const FormatException('JSON nesnesi değil');
      }
      return HubBackupOAuthCredentials.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      if (e is HubBackupOAuthException) rethrow;
      throw HubBackupOAuthException(
        'ERR_OAUTH_CORRUPT_STORE',
        'Hub Drive OAuth kasa içeriği okunamadı: $e',
      );
    }
  }

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
