import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'backup_crypto.dart';
import 'backup_file_transfer.dart';
import 'backup_manifest.dart';
import 'database_backup_engine.dart';
import 'resumable_drive_uploader.dart' show MmsDriveBackupFolders;

/// Faz 7D — Google Drive şifreli yedek (canlı senkronizasyon DEĞİL; ADR-011 `drive.file`).
///
/// Yalnızca zaten AES-256 + HMAC ile şifrelenmiş `.mmsbak` paketleri yüklenir.
/// Drive'a erişilemezse yerel yedekleme etkilenmez; yükleme bir sonraki turda
/// [GoogleDriveBackupUploader.uploadPending] ile tekrar denenir.

class DriveBackupException implements Exception {
  final String code;
  final String message;
  const DriveBackupException(this.code, this.message);

  @override
  String toString() => 'DriveBackupException [$code]: $message';
}

/// Drive API erişim token'ı sağlayıcısı (gerçek uygulama: OAuth refresh token).
abstract class DriveAccessTokenProvider {
  Future<String> accessToken({bool forceRefresh = false});
}

const String googleDriveFileScope = 'https://www.googleapis.com/auth/drive.file';
final Uri _googleTokenEndpoint = Uri.parse('https://oauth2.googleapis.com/token');

/// OAuth 2.0 refresh token ile kısa ömürlü erişim token'ı üretir ve önbelleğe alır.
/// Refresh token yalnızca güvenli depoda (DPAPI / Android Keystore) tutulur.
class GoogleOAuthRefreshTokenProvider implements DriveAccessTokenProvider {
  final String clientId;
  final String? clientSecret; // Masaüstü (installed app) istemcilerinde gizli sayılmaz.
  final Future<String?> Function() readRefreshToken;
  final http.Client httpClient;
  final DateTime Function() clock;

  String? _cached;
  DateTime? _expiresAt;

  GoogleOAuthRefreshTokenProvider({
    required this.clientId,
    required this.readRefreshToken,
    required this.httpClient,
    this.clientSecret,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    final cached = _cached;
    if (!forceRefresh && cached != null && _expiresAt != null && clock().isBefore(_expiresAt!)) {
      return cached;
    }
    final refresh = await readRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      throw const DriveBackupException(
        'ERR_DRIVE_NOT_AUTHORIZED',
        'Google Drive yetkilendirmesi yapılmamış. Owner, Ayarlar > Yedekleme bölümünden Google hesabını bağlamalıdır.',
      );
    }
    final http.Response resp;
    try {
      resp = await httpClient.post(_googleTokenEndpoint, body: {
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
        'client_id': clientId,
        if (clientSecret != null) 'client_secret': clientSecret!,
      });
    } on Exception catch (e) {
      throw DriveBackupException('ERR_DRIVE_UNAVAILABLE', 'Google kimlik sunucusuna ulaşılamadı: ${_safe(e)}');
    }
    final body = _decodeObject(resp.body);
    if (resp.statusCode == 400 || resp.statusCode == 401) {
      _cached = null;
      throw DriveBackupException(
        'ERR_DRIVE_REAUTH_REQUIRED',
        'Google Drive yetkisi geçersiz veya iptal edilmiş (${body['error'] ?? resp.statusCode}); hesabı yeniden bağlayın.',
      );
    }
    final token = body['access_token'];
    if (resp.statusCode != 200 || token is! String) {
      throw DriveBackupException('ERR_DRIVE_UNAVAILABLE', 'Erişim token\'ı alınamadı (HTTP ${resp.statusCode}).');
    }
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 3600;
    _cached = token;
    // 60 sn güvenlik payı: token istek ortasında süresi dolmasın.
    _expiresAt = clock().add(Duration(seconds: max(0, expiresIn - 60)));
    return token;
  }

  /// Bellekte önbelleklenen kısa ömürlü erişim token'ını sıfırlar.
  void clearCachedAccessToken() {
    _cached = null;
    _expiresAt = null;
  }

  /// Google OAuth 2.0 `revoke` ucu üzerinden refresh/access token'ı iptal eder.
  Future<bool> revokeToken() async {
    final refresh = await readRefreshToken();
    final tokenToRevoke = (refresh != null && refresh.isNotEmpty) ? refresh : _cached;
    clearCachedAccessToken();
    if (tokenToRevoke == null || tokenToRevoke.isEmpty) {
      return false;
    }
    try {
      final resp = await httpClient
          .post(
            Uri.parse('https://oauth2.googleapis.com/revoke'),
            headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {'token': tokenToRevoke},
          )
          .timeout(const Duration(seconds: 15));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

class GoogleOAuthTokens {
  final String accessToken;
  final String? refreshToken;
  final int expiresInSeconds;
  const GoogleOAuthTokens({required this.accessToken, required this.refreshToken, required this.expiresInSeconds});
}

class GoogleOAuthSession {
  final Uri authorizationUri;
  final String codeVerifier;
  final String state;
  final String redirectUri;
  const GoogleOAuthSession({
    required this.authorizationUri,
    required this.codeVerifier,
    required this.state,
    required this.redirectUri,
  });
}

/// Masaüstü (loopback yönlendirme + PKCE) OAuth akışı. Owner tarayıcıda Google
/// hesabını onaylar; uygulama `127.0.0.1` üzerindeki geri dönüş adresinden kodu alır.
class GoogleOAuthDesktopFlow {
  final String clientId;
  final String? clientSecret;
  final http.Client httpClient;
  static final Random _random = Random.secure();

  GoogleOAuthDesktopFlow({required this.clientId, required this.httpClient, this.clientSecret});

  static String _randomUrlSafe(int bytes) =>
      base64UrlEncode(List<int>.generate(bytes, (_) => _random.nextInt(256))).replaceAll('=', '');

  GoogleOAuthSession begin({required String redirectUri}) {
    final verifier = _randomUrlSafe(48); // 64 karakter (RFC 7636: 43-128)
    final challenge = base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = _randomUrlSafe(24);
    final uri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': googleDriveFileScope,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
      'prompt': 'consent',
      'state': state,
    });
    return GoogleOAuthSession(authorizationUri: uri, codeVerifier: verifier, state: state, redirectUri: redirectUri);
  }

  Future<GoogleOAuthTokens> complete(GoogleOAuthSession session, Uri callback) async {
    final params = callback.queryParameters;
    if (params['state'] != session.state) {
      throw const DriveBackupException('ERR_OAUTH_STATE_MISMATCH', 'Yetkilendirme yanıtı doğrulanamadı (state uyuşmuyor).');
    }
    if (params['error'] != null) {
      throw DriveBackupException('ERR_OAUTH_DENIED', 'Google yetkilendirmesi reddedildi: ${params['error']}');
    }
    final code = params['code'];
    if (code == null || code.isEmpty) {
      throw const DriveBackupException('ERR_OAUTH_DENIED', 'Yetkilendirme kodu alınamadı.');
    }
    final resp = await httpClient.post(_googleTokenEndpoint, body: {
      'grant_type': 'authorization_code',
      'code': code,
      'code_verifier': session.codeVerifier,
      'redirect_uri': session.redirectUri,
      'client_id': clientId,
      if (clientSecret != null) 'client_secret': clientSecret!,
    });
    final body = _decodeObject(resp.body);
    final access = body['access_token'];
    if (resp.statusCode != 200 || access is! String) {
      throw DriveBackupException('ERR_OAUTH_EXCHANGE_FAILED', 'Yetkilendirme kodu değiştirilemedi (HTTP ${resp.statusCode}).');
    }
    return GoogleOAuthTokens(
      accessToken: access,
      refreshToken: body['refresh_token'] as String?,
      expiresInSeconds: (body['expires_in'] as num?)?.toInt() ?? 3600,
    );
  }
}

class DriveUploadEntry {
  final String backupId;
  final String sha256Hex;
  final String driveFileId;
  final int sizeBytes;
  final DateTime uploadedAt;

  const DriveUploadEntry({
    required this.backupId,
    required this.sha256Hex,
    required this.driveFileId,
    required this.sizeBytes,
    required this.uploadedAt,
  });

  Map<String, dynamic> toJson() => {
        'backup_id': backupId,
        'sha256': sha256Hex,
        'drive_file_id': driveFileId,
        'size_bytes': sizeBytes,
        'uploaded_at': uploadedAt.toUtc().toIso8601String(),
      };

  factory DriveUploadEntry.fromJson(Map<String, dynamic> j) => DriveUploadEntry(
        backupId: j['backup_id'] as String,
        sha256Hex: j['sha256'] as String,
        driveFileId: j['drive_file_id'] as String,
        sizeBytes: (j['size_bytes'] as num).toInt(),
        uploadedAt: DateTime.parse(j['uploaded_at'] as String),
      );
}

class DriveUploadLedgerState {
  final Map<String, DriveUploadEntry> entries;
  final String? folderId;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;

  const DriveUploadLedgerState({
    this.entries = const {},
    this.folderId,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.lastErrorCode,
    this.lastErrorMessage,
  });

  Map<String, dynamic> toJson() => {
        'version': 1,
        'folder_id': folderId,
        'last_success_at': lastSuccessAt?.toUtc().toIso8601String(),
        'last_failure_at': lastFailureAt?.toUtc().toIso8601String(),
        'last_error_code': lastErrorCode,
        'last_error_message': lastErrorMessage,
        'entries': entries.values.map((e) => e.toJson()).toList(),
      };

  factory DriveUploadLedgerState.fromJson(Map<String, dynamic> j) {
    DateTime? ts(Object? raw) => raw is String ? DateTime.parse(raw) : null;
    final list = ((j['entries'] as List?) ?? const []).whereType<Map>().map(
          (m) => DriveUploadEntry.fromJson(Map<String, dynamic>.from(m)),
        );
    return DriveUploadLedgerState(
      entries: {for (final e in list) e.backupId: e},
      folderId: j['folder_id'] as String?,
      lastSuccessAt: ts(j['last_success_at']),
      lastFailureAt: ts(j['last_failure_at']),
      lastErrorCode: j['last_error_code'] as String?,
      lastErrorMessage: j['last_error_message'] as String?,
    );
  }
}

/// Yükleme geçmişi ve tekrar yükleme koruması (atomik JSON dosyası).
class DriveUploadLedger {
  final File file;
  DriveUploadLedger(this.file);

  Future<DriveUploadLedgerState> load() async {
    if (!await file.exists()) return const DriveUploadLedgerState();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) return DriveUploadLedgerState.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException catch (e) {
      final quarantine = '${file.path}.corrupt_${DateTime.now().millisecondsSinceEpoch}';
      await file.rename(quarantine);
      stderr.writeln('[DriveLedger] Kayıt dosyası bozuk (${e.message}); ${p.basename(quarantine)} olarak saklandı.');
    }
    return const DriveUploadLedgerState();
  }

  Future<void> save(DriveUploadLedgerState state) async {
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}

class DriveUploadRecord {
  final String backupId;
  final String driveFileId;
  final bool skipped;
  const DriveUploadRecord({required this.backupId, required this.driveFileId, required this.skipped});
}

/// Drive v3 REST üzerinden şifreli yedek yükleyici (resumable upload).
class GoogleDriveBackupUploader {
  static const String folderName = MmsDriveBackupFolders.rootFolderName;
  static const String _folderMime = 'application/vnd.google-apps.folder';

  final DriveAccessTokenProvider tokenProvider;
  final http.Client httpClient;
  final DriveUploadLedger ledger;
  final int maxAttempts;
  final Duration baseDelay;
  final Future<void> Function(Duration) delay;
  final Duration requestTimeout;

  GoogleDriveBackupUploader({
    required this.tokenProvider,
    required this.httpClient,
    required this.ledger,
    this.maxAttempts = 4,
    this.baseDelay = const Duration(seconds: 2),
    Future<void> Function(Duration)? delay,
    this.requestTimeout = const Duration(minutes: 2),
  }) : delay = delay ?? Future<void>.delayed;

  Future<DriveUploadRecord> upload({required File backupFile, required BackupManifest manifest}) async {
    final bytes = await backupFile.readAsBytes();
    _ensureEncryptedPackageFor(bytes, manifest);
    final sha = sha256.convert(bytes).toString();
    var state = await ledger.load();

    final known = state.entries[manifest.backupId];
    if (known != null && known.sha256Hex == sha) {
      return DriveUploadRecord(backupId: manifest.backupId, driveFileId: known.driveFileId, skipped: true);
    }

    try {
      final existingId = await _findExisting(manifest.backupId);
      if (existingId != null) {
        state = _withEntry(state, manifest.backupId, sha, existingId, bytes.length);
        await ledger.save(state);
        return DriveUploadRecord(backupId: manifest.backupId, driveFileId: existingId, skipped: true);
      }

      final folderId = state.folderId ?? await _ensureFolder();
      final fileId = await _resumableUpload(
        name: p.basename(backupFile.path),
        folderId: folderId,
        bytes: bytes,
        appProperties: {
          'mms_backup_id': manifest.backupId,
          'mms_sha256': sha,
          'mms_device_id': manifest.deviceId,
          'mms_tenant_id': manifest.tenantId,
          'mms_store_id': manifest.storeId,
          'mms_database_type': manifest.databaseType.value,
          'mms_schema_version': manifest.schemaVersion.toString(),
        },
      );
      state = _withEntry(
        DriveUploadLedgerState(
          entries: state.entries,
          folderId: folderId,
          lastSuccessAt: state.lastSuccessAt,
        ),
        manifest.backupId,
        sha,
        fileId,
        bytes.length,
      );
      await ledger.save(state);
      return DriveUploadRecord(backupId: manifest.backupId, driveFileId: fileId, skipped: false);
    } on DriveBackupException catch (e) {
      await ledger.save(DriveUploadLedgerState(
        entries: state.entries,
        folderId: state.folderId,
        lastSuccessAt: state.lastSuccessAt,
        lastFailureAt: DateTime.now().toUtc(),
        lastErrorCode: e.code,
        lastErrorMessage: e.message,
      ));
      rethrow;
    }
  }

  /// ADR-011/016: Drive'a yalnızca şifreli `.mmsbak` paketi gider. Ağ isteğinden ÖNCE
  /// paket başlığı/manifesti okunur ve çağıranın verdiği yedekle eşleştirilir; şifresiz
  /// SQLite (ör. güvenlik kopyası) veya yanlış dosya hiçbir koşulda yüklenmez.
  static void _ensureEncryptedPackageFor(Uint8List bytes, BackupManifest expected) {
    final BackupManifest embedded;
    try {
      embedded = BackupCryptoService.extractManifestWithoutDecryption(bytes);
    } on Object catch (e) {
      throw DriveBackupException(
        'ERR_DRIVE_NOT_ENCRYPTED_PACKAGE',
        'Dosya şifreli MARKET MMS yedek paketi değil; Drive\'a yüklenmedi (${e.runtimeType}).',
      );
    }
    if (embedded.backupId != expected.backupId ||
        embedded.deviceId != expected.deviceId ||
        embedded.databaseType != expected.databaseType) {
      throw const DriveBackupException(
        'ERR_DRIVE_NOT_ENCRYPTED_PACKAGE',
        'Dosyadaki yedek kimliği beklenen yedekle eşleşmiyor; Drive\'a yüklenmedi.',
      );
    }
  }

  /// Henüz Drive'a gitmemiş yerel yedekleri (ör. önceki turda bağlantı yoktu) yükler.
  Future<List<DriveUploadRecord>> uploadPending(
    List<({File file, BackupManifest manifest})> localBackups,
  ) async {
    final results = <DriveUploadRecord>[];
    for (final b in localBackups) {
      results.add(await upload(backupFile: b.file, manifest: b.manifest));
    }
    return results;
  }

  DriveUploadLedgerState _withEntry(DriveUploadLedgerState s, String id, String sha, String fileId, int size) {
    final now = DateTime.now().toUtc();
    return DriveUploadLedgerState(
      entries: {
        ...s.entries,
        id: DriveUploadEntry(backupId: id, sha256Hex: sha, driveFileId: fileId, sizeBytes: size, uploadedAt: now),
      },
      folderId: s.folderId,
      lastSuccessAt: now,
    );
  }

  Future<String?> _findExisting(String backupId) async {
    final q = "appProperties has { key='mms_backup_id' and value = '${_escape(backupId)}' } and trashed = false";
    final resp = await _send((token) => httpClient.get(
          Uri.https('www.googleapis.com', '/drive/v3/files', {'q': q, 'fields': 'files(id,name)', 'spaces': 'drive'}),
          headers: {'authorization': 'Bearer $token'},
        ));
    final files = _decodeObject(resp.body)['files'];
    if (files is List && files.isNotEmpty) return (files.first as Map)['id'] as String?;
    return null;
  }

  Future<String> _ensureFolder() async {
    final q = "mimeType = '$_folderMime' and name = '${_escape(folderName)}' and trashed = false";
    final found = await _send((token) => httpClient.get(
          Uri.https('www.googleapis.com', '/drive/v3/files', {'q': q, 'fields': 'files(id)', 'spaces': 'drive'}),
          headers: {'authorization': 'Bearer $token'},
        ));
    final files = _decodeObject(found.body)['files'];
    if (files is List && files.isNotEmpty) return (files.first as Map)['id'] as String;
    final created = await _send((token) => httpClient.post(
          Uri.https('www.googleapis.com', '/drive/v3/files', {'fields': 'id'}),
          headers: {'authorization': 'Bearer $token', 'content-type': 'application/json; charset=UTF-8'},
          body: jsonEncode({'name': folderName, 'mimeType': _folderMime}),
        ));
    return _decodeObject(created.body)['id'] as String;
  }

  Future<String> _resumableUpload({
    required String name,
    required String folderId,
    required List<int> bytes,
    required Map<String, String> appProperties,
  }) async {
    final localMd5 = md5.convert(bytes).toString();
    final init = await _send((token) => httpClient.post(
          Uri.https('www.googleapis.com', '/upload/drive/v3/files', {'uploadType': 'resumable'}),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json; charset=UTF-8',
            'x-upload-content-type': 'application/octet-stream',
            'x-upload-content-length': '${bytes.length}',
          },
          body: jsonEncode({
            'name': name,
            'parents': [folderId],
            'mimeType': 'application/octet-stream',
            'appProperties': appProperties,
          }),
        ));
    final location = init.headers['location'];
    if (location == null) {
      throw const DriveBackupException('ERR_DRIVE_UNAVAILABLE', 'Drive yükleme oturumu başlatılamadı.');
    }
    final put = await _send((token) => httpClient.put(
          Uri.parse(location).replace(queryParameters: {
            ...Uri.parse(location).queryParameters,
            'fields': 'id,name,size,md5Checksum',
          }),
          headers: {'authorization': 'Bearer $token', 'content-type': 'application/octet-stream'},
          body: bytes,
        ));
    final meta = _decodeObject(put.body);
    final id = meta['id'] as String?;
    if (id == null) throw const DriveBackupException('ERR_DRIVE_UNAVAILABLE', 'Drive dosya kimliği dönmedi.');
    if (meta['size'] != '${bytes.length}' || meta['md5Checksum'] != localMd5) {
      await _send((token) => httpClient.delete(
            Uri.https('www.googleapis.com', '/drive/v3/files/$id'),
            headers: {'authorization': 'Bearer $token'},
          ));
      throw const DriveBackupException(
        'ERR_DRIVE_VERIFY_FAILED',
        'Drive\'a yüklenen dosya doğrulanamadı (boyut/MD5 uyuşmuyor); bozuk kopya silindi, sonraki turda tekrar denenecek.',
      );
    }
    return id;
  }

  /// 401 → token bir kez yenilenir; 429/5xx/ağ hatası → üstel bekleme ile yeniden dener.
  Future<http.Response> _send(Future<http.Response> Function(String token) request) async {
    var refreshed = false;
    for (var attempt = 1;; attempt++) {
      try {
        final token = await tokenProvider.accessToken();
        final resp = await request(token).timeout(requestTimeout);
        if (resp.statusCode == 401 && !refreshed) {
          refreshed = true;
          await tokenProvider.accessToken(forceRefresh: true);
          attempt = 0;
          continue;
        }
        if (resp.statusCode >= 200 && resp.statusCode < 300) return resp;
        final transient = resp.statusCode == 429 || resp.statusCode >= 500;
        if (!transient) {
          throw DriveBackupException(
            resp.statusCode == 401 || resp.statusCode == 403 ? 'ERR_DRIVE_REAUTH_REQUIRED' : 'ERR_DRIVE_REJECTED',
            'Drive isteği reddedildi (HTTP ${resp.statusCode}).',
          );
        }
        if (attempt >= maxAttempts) {
          throw DriveBackupException('ERR_DRIVE_UNAVAILABLE', 'Drive geçici olarak kullanılamıyor (HTTP ${resp.statusCode}).');
        }
      } on DriveBackupException {
        rethrow;
      } on Exception catch (e) {
        if (attempt >= maxAttempts) {
          throw DriveBackupException('ERR_DRIVE_UNAVAILABLE', 'Drive\'a ulaşılamadı: ${_safe(e)}');
        }
      }
      await delay(baseDelay * (1 << (attempt - 1)));
    }
  }

  /// Google Drive klasöründeki şifreli `.mmsbak` yedeklerini listeler (en yeniden eskiye).
  Future<List<DriveRemoteBackupInfo>> listRemoteBackups({
    String? tenantId,
    String? storeId,
    String? deviceId,
    DatabaseType? databaseType,
  }) async {
    final folderId = await _findFolderIdOnly();
    if (folderId == null) return const [];

    final items = <DriveRemoteBackupInfo>[];
    String? pageToken;
    do {
      final queryParams = <String, String>{
        'q': "'${_escape(folderId)}' in parents and trashed = false",
        'fields': 'nextPageToken,files(id,name,size,createdTime,appProperties)',
        'spaces': 'drive',
        'pageSize': '100',
        'orderBy': 'createdTime desc',
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      };
      final resp = await _send(
        (token) => httpClient.get(
          Uri.https('www.googleapis.com', '/drive/v3/files', queryParams),
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      final body = _decodeObject(resp.body);
      final files = body['files'] as List<dynamic>? ?? const [];
      for (final raw in files) {
        if (raw is! Map) continue;
        final info = DriveRemoteBackupInfo.tryParse(Map<String, dynamic>.from(raw));
        if (info == null) continue;
        // S5: Eski istemci (ADR-016/021) geri yükleme listesi merkezi Hub yedeklerini
        // (ADR-023) asla göstermez; geçiş öncesi kök klasörde kalmış Hub dosyaları dahil.
        if (info.isHubCentralBackup) continue;
        if (tenantId != null && info.tenantId != null && info.tenantId != tenantId) {
          continue;
        }
        if (storeId != null && info.storeId != null && info.storeId != storeId) {
          continue;
        }
        if (deviceId != null && info.deviceId != null && info.deviceId != deviceId) {
          continue;
        }
        if (databaseType != null &&
            info.databaseType != null &&
            info.databaseType != databaseType) {
          continue;
        }
        items.add(info);
      }
      final next = body['nextPageToken'];
      pageToken = next is String && next.isNotEmpty ? next : null;
    } while (pageToken != null);

    items.sort((a, b) {
      final cmp = (b.createdTimeUtc ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
          .compareTo(a.createdTimeUtc ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      return cmp != 0 ? cmp : b.fileName.compareTo(a.fileName);
    });
    return items;
  }

  /// Şifreli `.mmsbak` paketini `.part` geçici dosyasıyla (Range destekli) indirir,
  /// boyut + SHA-256 + paket yapısı doğrulamasından geçirip atomik olarak `.mmsbak` dosyasına alır.
  /// Bozuk `.part` indirilen dosya asla korunmaz, otomatik silinir.
  Future<File> downloadEncryptedBackup({
    required DriveRemoteBackupInfo remote,
    required Directory targetDir,
  }) async {
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final safeName = p.basename(remote.fileName).trim();
    if (safeName.isEmpty || !safeName.endsWith('.mmsbak')) {
      throw const DriveBackupException(
        'ERR_DRIVE_NOT_ENCRYPTED_PACKAGE',
        'Uzak dosya adı geçerli bir .mmsbak yedek paketi değil.',
      );
    }
    final finalFile = File(p.join(targetDir.path, safeName));
    final partFile = File('${finalFile.path}.part');

    var offset = 0;
    if (await partFile.exists()) {
      final existingLen = await partFile.length();
      if (remote.sizeBytes > 0 && existingLen >= remote.sizeBytes) {
        await partFile.delete();
        offset = 0;
      } else {
        offset = existingLen;
      }
    }

    final downloadUri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files/${Uri.encodeComponent(remote.fileId)}',
      const {'alt': 'media'},
    );

    try {
      http.Response resp;
      try {
        resp = await _send(
          (token) => httpClient.get(
            downloadUri,
            headers: {
              'Authorization': 'Bearer $token',
              if (offset > 0) 'Range': 'bytes=$offset-',
            },
          ),
        );
      } on DriveBackupException catch (e) {
        // Stale Range (416): yarım kalmış .part dosyasını sil ve baştan indir.
        if (offset > 0 && e.message.contains('HTTP 416')) {
          if (await partFile.exists()) await partFile.delete();
          offset = 0;
          resp = await _send(
            (token) => httpClient.get(
              downloadUri,
              headers: {'Authorization': 'Bearer $token'},
            ),
          );
        } else {
          rethrow;
        }
      }

      if (offset > 0 && resp.statusCode == 206) {
        await partFile.writeAsBytes(resp.bodyBytes, mode: FileMode.append, flush: true);
      } else {
        await partFile.writeAsBytes(resp.bodyBytes, mode: FileMode.write, flush: true);
      }

      final bytes = await partFile.readAsBytes();
      if (remote.sizeBytes > 0 && bytes.length != remote.sizeBytes) {
        throw DriveBackupException(
          'ERR_DRIVE_DOWNLOAD_INCOMPLETE',
          'İndirilen yedek boyutu eksik veya uyuşmuyor '
              '(beklenen ${remote.sizeBytes}, alınan ${bytes.length}).',
        );
      }

      final expectedSha = remote.sha256Checksum?.trim().toLowerCase();
      if (expectedSha != null && expectedSha.isNotEmpty) {
        final actualSha = sha256.convert(bytes).toString().toLowerCase();
        if (!BackupCryptoService.constantTimeEquals(
          utf8.encode(actualSha),
          utf8.encode(expectedSha),
        )) {
          throw const DriveBackupException(
            'ERR_DRIVE_CHECKSUM_MISMATCH',
            'İndirilen yedek dosyasının SHA-256 özeti Drive kaydıyla uyuşmuyor.',
          );
        }
      }

      final BackupManifest manifest;
      try {
        manifest = BackupFileTransfer.verifyPackageStructure(bytes);
      } on BackupException catch (e) {
        throw DriveBackupException('ERR_DRIVE_NOT_ENCRYPTED_PACKAGE', e.message);
      }

      if (remote.backupId != null &&
          remote.backupId!.isNotEmpty &&
          manifest.backupId != remote.backupId) {
        throw const DriveBackupException(
          'ERR_DRIVE_CHECKSUM_MISMATCH',
          'İndirilen yedeğin kimliği seçilen yedekle uyuşmuyor.',
        );
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(finalFile.path);
      return finalFile;
    } catch (_) {
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (delErr) {
          stderr.writeln(
            '[GoogleDriveBackup] Bozuk .part dosyası silinemedi (${p.basename(partFile.path)}): ${delErr.runtimeType}',
          );
        }
      }
      rethrow;
    }
  }

  Future<String?> _findFolderIdOnly() async {
    final cached = (await ledger.load()).folderId;
    if (cached != null && cached.isNotEmpty) return cached;
    final q = "mimeType = '$_folderMime' and name = '${_escape(folderName)}' and trashed = false";
    final resp = await _send(
      (token) => httpClient.get(
        Uri.https('www.googleapis.com', '/drive/v3/files', {
          'q': q,
          'fields': 'files(id)',
          'spaces': 'drive',
        }),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    final files = (_decodeObject(resp.body)['files'] as List<dynamic>?) ?? const [];
    if (files.isEmpty) return null;
    final id = (files.first as Map)['id'] as String?;
    return (id != null && id.isNotEmpty) ? id : null;
  }
}

class DriveRemoteBackupInfo {
  final String fileId;
  final String fileName;
  final int sizeBytes;
  final DateTime? createdTimeUtc;
  final String? backupId;
  final String? deviceId;
  final String? tenantId;
  final String? storeId;
  final DatabaseType? databaseType;
  final int? schemaVersion;
  final String? sha256Checksum;

  /// S5: Merkezi Hub yedeği mi (`appProperties.mms_backup_source = HUB_CENTRAL` veya
  /// `hub_backup_` dosya adı öneki)? Eski istemci listeleri bunları dışlar.
  final bool isHubCentralBackup;

  const DriveRemoteBackupInfo({
    required this.fileId,
    required this.fileName,
    required this.sizeBytes,
    this.createdTimeUtc,
    this.backupId,
    this.deviceId,
    this.tenantId,
    this.storeId,
    this.databaseType,
    this.schemaVersion,
    this.sha256Checksum,
    this.isHubCentralBackup = false,
  });

  static DriveRemoteBackupInfo? tryParse(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    if (id == null || id.isEmpty || name == null || !name.endsWith('.mmsbak')) {
      return null;
    }
    final rawSize = json['size'];
    final sizeBytes = rawSize is int
        ? rawSize
        : (rawSize is num
            ? rawSize.toInt()
            : int.tryParse(rawSize?.toString() ?? '') ?? 0);
    final rawCreated = json['createdTime'] as String?;
    final createdTimeUtc =
        rawCreated != null ? DateTime.tryParse(rawCreated)?.toUtc() : null;
    final propsRaw = json['appProperties'];
    final props = propsRaw is Map
        ? Map<String, dynamic>.from(propsRaw)
        : const <String, dynamic>{};

    DatabaseType? dbType;
    final rawDbType = props['mms_database_type'] as String?;
    if (rawDbType != null && rawDbType.isNotEmpty) {
      try {
        dbType = DatabaseType.fromString(rawDbType);
      } catch (e) {
        stderr.writeln(
          '[GoogleDriveBackup] Geçersiz mms_database_type metadata ($rawDbType): ${e.runtimeType}',
        );
      }
    }

    String? backupId = props['mms_backup_id'] as String?;
    String? deviceId = props['mms_device_id'] as String?;
    if (backupId == null || backupId.isEmpty) {
      final stem = name.substring(0, name.length - '.mmsbak'.length);
      final idx = stem.lastIndexOf('_');
      if (idx > 0 && idx + 1 < stem.length) {
        backupId = stem.substring(idx + 1);
      }
    }

    return DriveRemoteBackupInfo(
      fileId: id,
      fileName: name,
      sizeBytes: sizeBytes,
      createdTimeUtc: createdTimeUtc,
      backupId: backupId,
      deviceId: deviceId,
      tenantId: props['mms_tenant_id'] as String?,
      storeId: props['mms_store_id'] as String?,
      databaseType: dbType,
      schemaVersion: int.tryParse(props['mms_schema_version']?.toString() ?? ''),
      sha256Checksum: props['mms_sha256'] as String?,
      isHubCentralBackup:
          props[MmsDriveBackupFolders.backupSourceProperty] == MmsDriveBackupFolders.hubBackupSource ||
              name.startsWith(MmsDriveBackupFolders.hubBackupFilePrefix),
    );
  }
}

String _escape(String v) => v.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

Map<String, dynamic> _decodeObject(String body) {
  if (body.isEmpty) return const {};
  try {
    final d = jsonDecode(body);
    return d is Map ? Map<String, dynamic>.from(d) : const {};
  } on FormatException {
    return const {};
  }
}

/// Hata metinlerinde token sızmasını önler (yalnızca istisna türü + kısa mesaj).
String _safe(Object e) {
  final text = e.toString();
  return text.replaceAll(RegExp(r'ya29\.[A-Za-z0-9_\-\.]+'), 'ya29.***').replaceAll(RegExp(r'1//[A-Za-z0-9_\-]+'), '1//***');
}
