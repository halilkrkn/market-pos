import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'backup_crypto.dart';
import 'backup_manifest.dart';
import 'database_backup_engine.dart';
import 'google_drive_backup.dart' show DriveBackupException;
import 'mmsbak_v2_crypto.dart';

/// Kooperatif yükleme iptal sinyali (ör. Hub kapanışında < 1.5s içinde iptal).
class BackupCancellationToken {
  bool _cancelled = false;
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _cancelled;
  Future<void> get onCancelled => _completer.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

enum DriveUploadFailureKind {
  cancelled,
  transient,
  authFailure,
  quotaExceeded,
  integrityVerificationFailed,
  invalidInput,
}

class DriveResumableUploadException implements Exception {
  final DriveUploadFailureKind kind;
  final String code;
  final String message;
  final int? statusCode;
  final String? sessionUri;
  final int uploadedBytes;

  const DriveResumableUploadException({
    required this.kind,
    required this.code,
    required this.message,
    this.statusCode,
    this.sessionUri,
    this.uploadedBytes = 0,
  });

  @override
  String toString() => 'DriveResumableUploadException [$code]: $message';
}

class ResumableDriveUploadResult {
  final String backupId;
  final String driveFileId;
  final String folderId;
  final int uploadedBytes;
  final String sha256Hex;
  final String md5Hex;

  const ResumableDriveUploadResult({
    required this.backupId,
    required this.driveFileId,
    required this.folderId,
    required this.uploadedBytes,
    required this.sha256Hex,
    required this.md5Hex,
  });
}

class HubDriveRemoteBackup {
  final String driveFileId;
  final String fileName;
  final String? backupId;
  final int sizeBytes;
  final String? sha256Hex;
  final String? md5Hex;
  final int? schemaVersion;
  final String? hubId;
  final DateTime? createdTimeUtc;
  final bool cachedLocally;

  const HubDriveRemoteBackup({
    required this.driveFileId,
    required this.fileName,
    this.backupId,
    required this.sizeBytes,
    this.sha256Hex,
    this.md5Hex,
    this.schemaVersion,
    this.hubId,
    this.createdTimeUtc,
    this.cachedLocally = false,
  });

  HubDriveRemoteBackup copyWith({bool? cachedLocally}) => HubDriveRemoteBackup(
        driveFileId: driveFileId,
        fileName: fileName,
        backupId: backupId,
        sizeBytes: sizeBytes,
        sha256Hex: sha256Hex,
        md5Hex: md5Hex,
        schemaVersion: schemaVersion,
        hubId: hubId,
        createdTimeUtc: createdTimeUtc,
        cachedLocally: cachedLocally ?? this.cachedLocally,
      );

  Map<String, dynamic> toJson() => {
        'drive_file_id': driveFileId,
        'file_name': fileName,
        'backup_id': backupId,
        'size_bytes': sizeBytes,
        'sha256_hex': sha256Hex,
        'md5_hex': md5Hex,
        'schema_version': schemaVersion,
        'hub_id': hubId,
        'created_time_utc': createdTimeUtc?.toUtc().toIso8601String(),
        'cached_locally': cachedLocally,
      };

  factory HubDriveRemoteBackup.fromJson(Map<String, dynamic> json) =>
      HubDriveRemoteBackup(
        driveFileId: json['drive_file_id'] as String,
        fileName: json['file_name'] as String,
        backupId: json['backup_id'] as String?,
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        sha256Hex: json['sha256_hex'] as String?,
        md5Hex: json['md5_hex'] as String?,
        schemaVersion: (json['schema_version'] as num?)?.toInt(),
        hubId: json['hub_id'] as String?,
        createdTimeUtc: json['created_time_utc'] is String
            ? DateTime.tryParse(json['created_time_utc'] as String)?.toUtc()
            : null,
        cachedLocally: (json['cached_locally'] as bool?) ?? false,
      );
}

class ResumableDriveDownloadResult {
  final File file;
  final String driveFileId;
  final BackupManifest manifest;
  final int sizeBytes;
  final String sha256Hex;

  const ResumableDriveDownloadResult({
    required this.file,
    required this.driveFileId,
    required this.manifest,
    required this.sizeBytes,
    required this.sha256Hex,
  });
}

class _SingleMd5Sink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) {
    digest = data;
  }

  @override
  void close() {}
}

class _SingleDigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) {
    digest = data;
  }

  @override
  void close() {}
}

typedef ResumableSessionProgressCallback = FutureOr<void> Function(
  String? sessionUri,
  int uploadedBytes,
);

/// S5 (`ADR-023` §Drive klasör ayrımı): Google Drive yedek klasör adları ve kaynak işareti.
///
/// - Eski istemci yedekleri (`GoogleDriveBackupUploader`): kök [rootFolderName]
///   (geriye dönük uyum; cihazlarda klasör geçişi gerekmez).
/// - Merkezi Hub yedekleri (`ADR-023`): [rootFolderName]/[hubSubfolderName].
/// - Hub yüklemeleri `appProperties.mms_backup_source = [hubBackupSource]` taşır; eski
///   istemci listesi bu işareti (veya `hub_backup_` dosya adı önekini) taşıyan
///   dosyaları göstermez. LiveSync klasörü (`MARKET MMS LiveSync`) bu sınıfın dışındadır.
abstract final class MmsDriveBackupFolders {
  static const String rootFolderName = 'MARKET MMS Yedekleri';
  static const String hubSubfolderName = 'Hub';
  static const String backupSourceProperty = 'mms_backup_source';
  static const String hubBackupSource = 'HUB_CENTRAL';
  static const String hubBackupFilePrefix = 'hub_backup_';
}

/// Faz B-2 (`ADR-023`): 4 MiB parça boyutlu, `RandomAccessFile` akışlı, HTTP 308
/// devam ettirmeli, oturum süresi (`404/410`) kurtarmalı ve `VERIFYING` doğrulamalı
/// Google Drive Resumable Yükleyici.
class ResumableDriveUploader {
  static const String defaultFolderName = MmsDriveBackupFolders.rootFolderName;
  static const int googleChunkAlignmentBytes = 256 * 1024;
  static const int defaultChunkSizeBytes = 4 * 1024 * 1024; // 4 MiB
  static final Uri _filesListEndpoint =
      Uri.parse('https://www.googleapis.com/drive/v3/files');
  static final Uri _resumableInitEndpoint =
      Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable');

  final Future<String> Function({bool forceRefresh}) accessTokenProvider;
  final http.Client httpClient;
  final int chunkSizeBytes;
  final Duration requestTimeout;
  final String folderName;

  /// Verilirse yüklemeler [folderName] altındaki bu alt klasöre yapılır (ör. `Hub`).
  final String? subfolderName;

  /// Her yüklemenin `appProperties` alanına eklenen sabit işaretler
  /// (ör. `mms_backup_source: HUB_CENTRAL`). Doğrulama alanlarını ezemez.
  final Map<String, String> extraAppProperties;
  final void Function(String message) _log;

  ResumableDriveUploader({
    required this.accessTokenProvider,
    required this.httpClient,
    this.chunkSizeBytes = defaultChunkSizeBytes,
    this.requestTimeout = const Duration(seconds: 30),
    this.folderName = defaultFolderName,
    this.subfolderName,
    this.extraAppProperties = const {},
    void Function(String message)? log,
  }) : _log = log ?? _defaultLog {
    if (chunkSizeBytes < googleChunkAlignmentBytes ||
        chunkSizeBytes % googleChunkAlignmentBytes != 0) {
      throw ArgumentError(
        'chunkSizeBytes 256 KiB (262144) tam katı olmalıdır: $chunkSizeBytes',
      );
    }
  }

  static void _defaultLog(String message) => stderr.writeln(message);

  Future<ResumableDriveUploadResult> uploadFile({
    required File encryptedFile,
    required BackupManifest manifest,
    String? knownFolderId,
    String? existingSessionUri,
    int existingUploadedBytes = 0,
    String? existingDriveFileId,
    ResumableSessionProgressCallback? onSessionProgress,
    FutureOr<void> Function(String driveFileId)? onBeforeVerify,
    BackupCancellationToken? cancellationToken,
  }) async {
    _throwIfCancelled(cancellationToken, existingSessionUri, existingUploadedBytes);
    if (!await encryptedFile.exists()) {
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.invalidInput,
        code: 'ERR_FILE_NOT_FOUND',
        message: 'Yüklenecek şifreli yedek dosyası bulunamadı: ${encryptedFile.path}',
      );
    }

    final totalBytes = await encryptedFile.length();
    if (totalBytes <= 0) {
      throw const DriveResumableUploadException(
        kind: DriveUploadFailureKind.invalidInput,
        code: 'ERR_EMPTY_BACKUP_PACKAGE',
        message: 'Şifreli yedek paketi boş.',
      );
    }

    // Yalnızca geçerli şifreli MMSBAK01/MMSBAK02 paketi yüklenir.
    await MmsbakV2Crypto.inspectFile(encryptedFile);
    final digests = await _computeFileSha256AndMd5(encryptedFile);

    final folderId = (knownFolderId != null && knownFolderId.isNotEmpty)
        ? knownFolderId
        : await _ensureFolder(
            cancellationToken: cancellationToken,
            sessionUri: existingSessionUri,
            uploadedBytes: existingUploadedBytes,
          );

    var sessionUri = existingSessionUri;
    var offset = existingUploadedBytes.clamp(0, totalBytes);
    String? completedFileId;

    // VERIFYING aşaması çökme kurtarması: driveFileId zaten kaydedilmişse yeniden
    // yüklemeden önce doğrudan Drive'daki dosyanın bütünlüğünü doğrulamayı dene.
    if (existingDriveFileId != null && existingDriveFileId.isNotEmpty) {
      await onBeforeVerify?.call(existingDriveFileId);
      _throwIfCancelled(cancellationToken, sessionUri, totalBytes);
      try {
        await _verifyRemoteFile(
          fileId: existingDriveFileId,
          expectedBackupId: manifest.backupId,
          expectedSizeBytes: totalBytes,
          expectedSha256Hex: digests.sha256Hex,
          expectedMd5Hex: digests.md5Hex,
          cancellationToken: cancellationToken,
          sessionUri: sessionUri,
        );
        return ResumableDriveUploadResult(
          backupId: manifest.backupId,
          driveFileId: existingDriveFileId,
          folderId: folderId,
          uploadedBytes: totalBytes,
          sha256Hex: digests.sha256Hex,
          md5Hex: digests.md5Hex,
        );
      } on DriveResumableUploadException catch (e) {
        if (e.statusCode != 404) rethrow;
        // Drive tarafında artık yoksa oturum/yeniden yükleme akışına düş.
      }
    }

    // Var olan sessionUri varsa HTTP 308 ofset sorgusuyla kaldığı yerden devam et.
    if (sessionUri != null && sessionUri.isNotEmpty) {
      final probe = await _probeSessionOffset(
        sessionUri: sessionUri,
        totalBytes: totalBytes,
        cancellationToken: cancellationToken,
      );
      if (probe.expired) {
        final existingRemoteId = await _findOrCleanupExistingRemoteFile(
          folderId: folderId,
          expectedBackupId: manifest.backupId,
          expectedSizeBytes: totalBytes,
          expectedSha256Hex: digests.sha256Hex,
          expectedMd5Hex: digests.md5Hex,
          cancellationToken: cancellationToken,
          sessionUri: sessionUri,
        );
        if (existingRemoteId != null) {
          completedFileId = existingRemoteId;
          offset = totalBytes;
        } else {
          sessionUri = null;
          offset = 0;
          await onSessionProgress?.call(null, 0);
        }
      } else if (probe.completedMissingId) {
        final existingRemoteId = await _findOrCleanupExistingRemoteFile(
          folderId: folderId,
          expectedBackupId: manifest.backupId,
          expectedSizeBytes: totalBytes,
          expectedSha256Hex: digests.sha256Hex,
          expectedMd5Hex: digests.md5Hex,
          cancellationToken: cancellationToken,
          sessionUri: sessionUri,
        );
        if (existingRemoteId != null) {
          completedFileId = existingRemoteId;
          offset = totalBytes;
        } else {
          throw DriveResumableUploadException(
            kind: DriveUploadFailureKind.integrityVerificationFailed,
            code: 'ERR_DRIVE_MISSING_FILE_ID',
            message: 'Drive oturum sorgusu tamamlandı yanıtında file id eksik.',
            sessionUri: sessionUri,
            uploadedBytes: existingUploadedBytes,
          );
        }
      } else if (probe.completedFileId != null) {
        completedFileId = probe.completedFileId;
        offset = totalBytes;
      } else {
        offset = probe.nextOffset >= totalBytes
            ? (totalBytes > 0 ? totalBytes - 1 : 0)
            : probe.nextOffset;
        await onSessionProgress?.call(sessionUri, offset);
      }
    }

    var recreatedExpiredSession = false;
    while (completedFileId == null) {
      _throwIfCancelled(cancellationToken, sessionUri, offset);

      if (sessionUri == null || sessionUri.isEmpty) {
        sessionUri = await _initiateResumableSession(
          folderId: folderId,
          fileName: p.basename(encryptedFile.path),
          totalBytes: totalBytes,
          manifest: manifest,
          encryptedSha256: digests.sha256Hex,
          cancellationToken: cancellationToken,
        );
        offset = 0;
        await onSessionProgress?.call(sessionUri, 0);
      }

      final raf = await encryptedFile.open(mode: FileMode.read);
      var sessionExpiredMidUpload = false;
      try {
        await raf.setPosition(offset);
        final buffer = List<int>.filled(chunkSizeBytes, 0);
        while (offset < totalBytes) {
          _throwIfCancelled(cancellationToken, sessionUri, offset);
          final remaining = totalBytes - offset;
          final toRead = min(chunkSizeBytes, remaining);
          await raf.setPosition(offset);
          final readCount = await _readExactInto(raf, buffer, toRead);
          final chunkBytes = buffer.sublist(0, readCount);
          final endByte = offset + readCount - 1;

          final resp = await _sendWithCancellation(
            () => httpClient
                .put(
                  Uri.parse(sessionUri!),
                  headers: {
                    'content-type': 'application/octet-stream',
                    'content-range': 'bytes $offset-$endByte/$totalBytes',
                  },
                  body: chunkBytes,
                )
                .timeout(requestTimeout),
            cancellationToken: cancellationToken,
            sessionUri: sessionUri,
            uploadedBytes: offset,
          );

          if (resp.statusCode == 308) {
            final parsedNext = _parseRangeNextOffset(resp.headers['range']);
            final candidateOffset = parsedNext ?? (endByte + 1);
            if (candidateOffset >= totalBytes) {
              throw DriveResumableUploadException(
                kind: DriveUploadFailureKind.transient,
                code: 'ERR_DRIVE_INCOMPLETE_FINALIZATION',
                message: 'Drive son parça sonrası dosya kimliği döndürmedi (HTTP 308).',
                statusCode: resp.statusCode,
                sessionUri: sessionUri,
                uploadedBytes: offset,
              );
            }
            offset = candidateOffset;
            await onSessionProgress?.call(sessionUri, offset);
            continue;
          }

          if (resp.statusCode == 200 || resp.statusCode == 201) {
            final decoded = _decodeJsonMap(resp.body);
            final fileId = decoded['id'];
            if (fileId is! String || fileId.isEmpty) {
              throw DriveResumableUploadException(
                kind: DriveUploadFailureKind.integrityVerificationFailed,
                code: 'ERR_DRIVE_MISSING_FILE_ID',
                message: 'Drive yükleme tamamlandı yanıtında file id eksik.',
                statusCode: resp.statusCode,
                sessionUri: sessionUri,
                uploadedBytes: offset,
              );
            }
            completedFileId = fileId;
            offset = totalBytes;
            await onSessionProgress?.call(sessionUri, totalBytes);
            break;
          }

          if (resp.statusCode == 404 || resp.statusCode == 410) {
            final existingRemoteId = await _findOrCleanupExistingRemoteFile(
              folderId: folderId,
              expectedBackupId: manifest.backupId,
              expectedSizeBytes: totalBytes,
              expectedSha256Hex: digests.sha256Hex,
              expectedMd5Hex: digests.md5Hex,
              cancellationToken: cancellationToken,
              sessionUri: sessionUri,
            );
            if (existingRemoteId != null) {
              completedFileId = existingRemoteId;
              offset = totalBytes;
              await onSessionProgress?.call(sessionUri, totalBytes);
              break;
            }
            if (!recreatedExpiredSession) {
              recreatedExpiredSession = true;
              sessionExpiredMidUpload = true;
              sessionUri = null;
              offset = 0;
              await onSessionProgress?.call(null, 0);
              break;
            }
          }

          throw _classifyHttpFailure(
            resp,
            sessionUri: sessionUri,
            uploadedBytes: offset,
          );
        }
      } finally {
        await raf.close();
      }

      if (!sessionExpiredMidUpload) {
        break;
      }
    }

    final finalFileId = completedFileId;
    if (finalFileId == null || finalFileId.isEmpty) {
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.integrityVerificationFailed,
        code: 'ERR_DRIVE_MISSING_FILE_ID',
        message: 'Drive yükleme tamamlandı yanıtında file id eksik.',
        sessionUri: sessionUri,
        uploadedBytes: offset,
      );
    }
    await onBeforeVerify?.call(finalFileId);
    _throwIfCancelled(cancellationToken, sessionUri, totalBytes);

    // VERIFYING aşaması: Güncel access token ile (401 durumunda 1x forceRefresh)
    // Drive meta verisi boyut + sha256/md5 doğrulaması.
    await _verifyRemoteFile(
      fileId: finalFileId,
      expectedBackupId: manifest.backupId,
      expectedSizeBytes: totalBytes,
      expectedSha256Hex: digests.sha256Hex,
      expectedMd5Hex: digests.md5Hex,
      cancellationToken: cancellationToken,
      sessionUri: sessionUri,
    );

    return ResumableDriveUploadResult(
      backupId: manifest.backupId,
      driveFileId: finalFileId,
      folderId: folderId,
      uploadedBytes: totalBytes,
      sha256Hex: digests.sha256Hex,
      md5Hex: digests.md5Hex,
    );
  }

  static final RegExp _safeDriveFileIdPattern =
      RegExp(r'^[A-Za-z0-9_\-]{1,200}$');

  static bool isValidDriveFileId(String id) =>
      _safeDriveFileIdPattern.hasMatch(id);

  /// Drive arşivinden tek bir yedek dosyasını siler (saklama budaması için).
  Future<void> deleteRemoteFile(String driveFileId) async {
    if (!isValidDriveFileId(driveFileId)) {
      throw const DriveResumableUploadException(
        kind: DriveUploadFailureKind.invalidInput,
        code: 'ERR_INVALID_DRIVE_FILE_ID',
        message: 'Geçersiz Google Drive dosya kimliği.',
      );
    }
    final resp = await _sendAuthenticated(
      (token) => httpClient
          .delete(
            Uri.parse('https://www.googleapis.com/drive/v3/files/$driveFileId'),
            headers: {'authorization': 'Bearer $token'},
          )
          .timeout(requestTimeout),
    );
    if (resp.statusCode != 200 && resp.statusCode != 204 && resp.statusCode != 404) {
      throw _classifyHttpFailure(resp);
    }
  }

  /// Google Drive `MARKET MMS Yedekleri/Hub` alt klasöründeki (ve geçiş öncesi
  /// kök klasörde kalmış `HUB_CENTRAL` / `hub_backup_` işaretli) `.mmsbak`
  /// yedeklerini listeler. `.mmsenv` ve istemci yerel yedekleri ASLA dönülmez.
  Future<List<HubDriveRemoteBackup>> listHubBackups({
    String? knownFolderId,
    BackupCancellationToken? cancellationToken,
  }) async {
    final folderIds = <String>[];
    final seenFolderIds = <String>{};

    if (knownFolderId != null && knownFolderId.isNotEmpty) {
      folderIds.add(knownFolderId);
      seenFolderIds.add(knownFolderId);
    }

    final rootId = await _findFolderIdOnly(
      name: folderName,
      cancellationToken: cancellationToken,
    );
    if (rootId != null) {
      final sub = subfolderName;
      if (sub != null && sub.isNotEmpty) {
        final hubFolderId = await _findFolderIdOnly(
          name: sub,
          parentId: rootId,
          cancellationToken: cancellationToken,
        );
        if (hubFolderId != null && seenFolderIds.add(hubFolderId)) {
          folderIds.add(hubFolderId);
        }
      }
      if (seenFolderIds.add(rootId)) {
        folderIds.add(rootId);
      }
    }

    if (folderIds.isEmpty) {
      return const [];
    }

    final itemsById = <String, HubDriveRemoteBackup>{};
    for (final fid in folderIds) {
      final isRootCheck = rootId != null && fid == rootId && subfolderName != null && subfolderName!.isNotEmpty;
      String? pageToken;
      do {
        final q = "'${_escape(fid)}' in parents and trashed = false";
        final listUri = _filesListEndpoint.replace(queryParameters: {
          'q': q,
          'fields': 'nextPageToken,files(id,name,size,md5Checksum,createdTime,appProperties)',
          'spaces': 'drive',
          'pageSize': '100',
          'orderBy': 'createdTime desc',
          if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
        });
        final resp = await _sendAuthenticated(
          (token) => httpClient
              .get(listUri, headers: {'authorization': 'Bearer $token'})
              .timeout(requestTimeout),
          cancellationToken: cancellationToken,
        );
        if (resp.statusCode != 200) {
          throw _classifyHttpFailure(resp);
        }
        final decoded = _decodeJsonMap(resp.body);
        final files = decoded['files'] as List? ?? const [];
        for (final raw in files) {
          if (raw is! Map) continue;
          final parsed = _tryParseHubRemoteBackup(
            Map<String, dynamic>.from(raw),
            requireExplicitHubMarker: isRootCheck,
          );
          if (parsed == null) continue;
          itemsById.putIfAbsent(parsed.driveFileId, () => parsed);
        }
        final next = decoded['nextPageToken'];
        pageToken = next is String && next.isNotEmpty ? next : null;
      } while (pageToken != null);
    }

    final result = itemsById.values.toList()
      ..sort((a, b) {
        final cmp = (b.createdTimeUtc ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
            .compareTo(a.createdTimeUtc ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
        return cmp != 0 ? cmp : b.fileName.compareTo(a.fileName);
      });
    return result;
  }

  /// Merkezi Hub yedek paketini `.part` dosyasına akışlı indirir; boyut, MD5,
  /// SHA-256 ve `MMSBAK01`/`MMSBAK02` şifreli paket yapısını doğrulamadan
  /// kalıcı `.mmsbak` dosyasına almaz. Hata durumunda `.part` otomatik silinir.
  Future<ResumableDriveDownloadResult> downloadAndVerifyBackup({
    required String driveFileId,
    required Directory targetDir,
    String? expectedBackupId,
    int? expectedSizeBytes,
    String? expectedSha256Hex,
    BackupCancellationToken? cancellationToken,
  }) async {
    _throwIfCancelled(cancellationToken, null, 0);
    if (!isValidDriveFileId(driveFileId)) {
      throw const DriveResumableUploadException(
        kind: DriveUploadFailureKind.invalidInput,
        code: 'ERR_INVALID_DRIVE_FILE_ID',
        message: 'Geçersiz Google Drive dosya kimliği.',
      );
    }

    final metaUri = Uri.parse(
      'https://www.googleapis.com/drive/v3/files/$driveFileId'
      '?fields=id,name,size,md5Checksum,createdTime,trashed,appProperties',
    );
    final metaResp = await _sendAuthenticated(
      (token) => httpClient
          .get(metaUri, headers: {'authorization': 'Bearer $token'})
          .timeout(requestTimeout),
      cancellationToken: cancellationToken,
    );
    if (metaResp.statusCode == 404) {
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.invalidInput,
        code: 'ERR_BACKUP_NOT_FOUND',
        message: 'Google Drive üzerinde yedek bulunamadı ($driveFileId).',
        statusCode: 404,
      );
    }
    if (metaResp.statusCode != 200) {
      throw _classifyHttpFailure(metaResp);
    }

    final meta = _decodeJsonMap(metaResp.body);
    if (meta['trashed'] == true) {
      throw const DriveResumableUploadException(
        kind: DriveUploadFailureKind.invalidInput,
        code: 'ERR_BACKUP_NOT_FOUND',
        message: 'Seçilen Google Drive yedeği çöp kutusunda.',
        statusCode: 404,
      );
    }

    final remoteName = (meta['name'] as String?)?.trim() ?? '';
    if (remoteName.isEmpty || !remoteName.endsWith('.mmsbak')) {
      throw const DriveResumableUploadException(
        kind: DriveUploadFailureKind.integrityVerificationFailed,
        code: 'ERR_DRIVE_INVALID_PACKAGE',
        message: 'Uzak Drive dosyası geçerli bir .mmsbak yedek paketi değil.',
      );
    }

    final appProps = meta['appProperties'] is Map
        ? Map<String, dynamic>.from(meta['appProperties'] as Map)
        : const <String, dynamic>{};
    final rawDbType = appProps['mms_database_type']?.toString();
    if (rawDbType != null &&
        rawDbType.isNotEmpty &&
        rawDbType != DatabaseType.centralMaster.value) {
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.integrityVerificationFailed,
        code: 'ERR_DATABASE_TYPE_MISMATCH',
        message: 'Drive dosyası merkezi Master Hub veritabanına ait değil ($rawDbType).',
      );
    }
    final rawSource = appProps[MmsDriveBackupFolders.backupSourceProperty]?.toString();
    if (rawSource != null &&
        rawSource.isNotEmpty &&
        rawSource != MmsDriveBackupFolders.hubBackupSource) {
      throw const DriveResumableUploadException(
        kind: DriveUploadFailureKind.integrityVerificationFailed,
        code: 'ERR_NOT_HUB_CENTRAL_BACKUP',
        message: 'Drive dosyası merkezi Hub yedek kaynağına ait değil.',
      );
    }

    final sizeRaw = meta['size'];
    final remoteSize = sizeRaw is int
        ? sizeRaw
        : int.tryParse(sizeRaw?.toString() ?? '') ?? 0;
    final remoteMd5 = (meta['md5Checksum'] as String?)?.trim().toLowerCase();
    final remoteSha = appProps['mms_sha256']?.toString().trim().toLowerCase();
    final remoteBackupId = appProps['mms_backup_id']?.toString().trim();

    if (expectedSizeBytes != null &&
        expectedSizeBytes > 0 &&
        remoteSize > 0 &&
        remoteSize != expectedSizeBytes) {
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.integrityVerificationFailed,
        code: 'ERR_DRIVE_DOWNLOAD_SIZE_MISMATCH',
        message:
            'Drive dosya boyutu yerel kayıtla uyuşmuyor ($remoteSize != $expectedSizeBytes).',
      );
    }
    if (expectedSha256Hex != null &&
        expectedSha256Hex.isNotEmpty &&
        remoteSha != null &&
        remoteSha.isNotEmpty &&
        !BackupCryptoService.constantTimeEquals(
          utf8.encode(remoteSha),
          utf8.encode(expectedSha256Hex.trim().toLowerCase()),
        )) {
      throw const DriveResumableUploadException(
        kind: DriveUploadFailureKind.integrityVerificationFailed,
        code: 'ERR_DRIVE_DOWNLOAD_CHECKSUM_MISMATCH',
        message: 'Drive dosya SHA-256 özeti beklenen kayıtla uyuşmuyor.',
      );
    }
    if (expectedBackupId != null &&
        expectedBackupId.isNotEmpty &&
        remoteBackupId != null &&
        remoteBackupId.isNotEmpty &&
        remoteBackupId != expectedBackupId) {
      throw const DriveResumableUploadException(
        kind: DriveUploadFailureKind.integrityVerificationFailed,
        code: 'ERR_DRIVE_VERIFY_BACKUP_ID_MISMATCH',
        message: 'Drive dosya mms_backup_id değeri seçilen yedekle uyuşmuyor.',
      );
    }

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final safeBaseName = p.basename(remoteName).trim();
    final finalFile = File(p.join(targetDir.path, safeBaseName));
    final partFile = File('${finalFile.path}.part');
    if (await partFile.exists()) {
      await partFile.delete();
    }

    final downloadUri = Uri.parse(
      'https://www.googleapis.com/drive/v3/files/$driveFileId?alt=media',
    );
    IOSink? sink;
    try {
      final streamResp = await _sendStreamAuthenticated(
        (token) {
          final req = http.Request('GET', downloadUri);
          req.headers['authorization'] = 'Bearer $token';
          return httpClient.send(req).timeout(requestTimeout);
        },
        cancellationToken: cancellationToken,
      );
      if (streamResp.statusCode == 404) {
        await streamResp.stream.drain<void>();
        throw DriveResumableUploadException(
          kind: DriveUploadFailureKind.invalidInput,
          code: 'ERR_BACKUP_NOT_FOUND',
          message: 'Google Drive üzerinde yedek içeriği bulunamadı ($driveFileId).',
          statusCode: 404,
        );
      }
      if (streamResp.statusCode != 200) {
        final errBody = await streamResp.stream.bytesToString();
        throw _classifyHttpFailure(
          http.Response(errBody, streamResp.statusCode),
        );
      }

      sink = partFile.openWrite();
      final shaSink = _SingleDigestSink();
      final md5Sink = _SingleMd5Sink();
      final shaHasher = sha256.startChunkedConversion(shaSink);
      final md5Hasher = md5.startChunkedConversion(md5Sink);
      var downloadedBytes = 0;

      await for (final chunk in streamResp.stream) {
        _throwIfCancelled(cancellationToken, null, downloadedBytes);
        if (chunk.isEmpty) continue;
        downloadedBytes += chunk.length;
        if (remoteSize > 0 && downloadedBytes > remoteSize) {
          throw DriveResumableUploadException(
            kind: DriveUploadFailureKind.integrityVerificationFailed,
            code: 'ERR_DRIVE_DOWNLOAD_SIZE_MISMATCH',
            message:
                'Drive akışı beklenen boyutu aştı ($downloadedBytes > $remoteSize).',
          );
        }
        sink.add(chunk);
        shaHasher.add(chunk);
        md5Hasher.add(chunk);
      }

      await sink.flush();
      await sink.close();
      sink = null;
      shaHasher.close();
      md5Hasher.close();

      if (downloadedBytes <= 0) {
        throw const DriveResumableUploadException(
          kind: DriveUploadFailureKind.integrityVerificationFailed,
          code: 'ERR_DRIVE_DOWNLOAD_SIZE_MISMATCH',
          message: 'Drive üzerinden indirilen yedek dosyası boş.',
        );
      }
      if (remoteSize > 0 && downloadedBytes != remoteSize) {
        throw DriveResumableUploadException(
          kind: DriveUploadFailureKind.integrityVerificationFailed,
          code: 'ERR_DRIVE_DOWNLOAD_SIZE_MISMATCH',
          message:
              'İndirilen yedek boyutu uyuşmuyor ($downloadedBytes != $remoteSize).',
        );
      }
      if (expectedSizeBytes != null &&
          expectedSizeBytes > 0 &&
          downloadedBytes != expectedSizeBytes) {
        throw DriveResumableUploadException(
          kind: DriveUploadFailureKind.integrityVerificationFailed,
          code: 'ERR_DRIVE_DOWNLOAD_SIZE_MISMATCH',
          message:
              'İndirilen yedek boyutu kayıtlı boyutla uyuşmuyor ($downloadedBytes != $expectedSizeBytes).',
        );
      }

      final actualSha = shaSink.digest.toString().toLowerCase();
      final actualMd5 = md5Sink.digest.toString().toLowerCase();
      if (remoteSha != null &&
          remoteSha.isNotEmpty &&
          !BackupCryptoService.constantTimeEquals(
            utf8.encode(actualSha),
            utf8.encode(remoteSha),
          )) {
        throw const DriveResumableUploadException(
          kind: DriveUploadFailureKind.integrityVerificationFailed,
          code: 'ERR_DRIVE_DOWNLOAD_CHECKSUM_MISMATCH',
          message: 'İndirilen yedek dosyasının SHA-256 özeti Drive meta verisiyle uyuşmuyor.',
        );
      }
      if (expectedSha256Hex != null &&
          expectedSha256Hex.isNotEmpty &&
          !BackupCryptoService.constantTimeEquals(
            utf8.encode(actualSha),
            utf8.encode(expectedSha256Hex.trim().toLowerCase()),
          )) {
        throw const DriveResumableUploadException(
          kind: DriveUploadFailureKind.integrityVerificationFailed,
          code: 'ERR_DRIVE_DOWNLOAD_CHECKSUM_MISMATCH',
          message: 'İndirilen yedek dosyasının SHA-256 özeti beklenen kayıtla uyuşmuyor.',
        );
      }
      if (remoteMd5 != null &&
          remoteMd5.isNotEmpty &&
          !BackupCryptoService.constantTimeEquals(
            utf8.encode(actualMd5),
            utf8.encode(remoteMd5),
          )) {
        throw const DriveResumableUploadException(
          kind: DriveUploadFailureKind.integrityVerificationFailed,
          code: 'ERR_DRIVE_DOWNLOAD_CHECKSUM_MISMATCH',
          message: 'İndirilen yedek dosyasının MD5 özeti uyuşmuyor.',
        );
      }

      final InspectedBackupPackage inspected;
      try {
        inspected = await MmsbakV2Crypto.inspectFile(partFile);
      } on BackupException catch (e) {
        throw DriveResumableUploadException(
          kind: DriveUploadFailureKind.integrityVerificationFailed,
          code: 'ERR_DRIVE_INVALID_PACKAGE',
          message: 'İndirilen dosya geçerli şifreli .mmsbak paketi değil: ${e.message}',
        );
      }

      if (inspected.manifest.databaseType != DatabaseType.centralMaster) {
        throw DriveResumableUploadException(
          kind: DriveUploadFailureKind.integrityVerificationFailed,
          code: 'ERR_DATABASE_TYPE_MISMATCH',
          message:
              'İndirilen paket Master Hub veritabanına ait değil (${inspected.manifest.databaseType.value}).',
        );
      }
      final checkBackupId = expectedBackupId ?? remoteBackupId;
      if (checkBackupId != null &&
          checkBackupId.isNotEmpty &&
          inspected.manifest.backupId != checkBackupId) {
        throw const DriveResumableUploadException(
          kind: DriveUploadFailureKind.integrityVerificationFailed,
          code: 'ERR_DRIVE_VERIFY_BACKUP_ID_MISMATCH',
          message: 'İndirilen paketin manifest backup_id değeri uyuşmuyor.',
        );
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(finalFile.path);
      return ResumableDriveDownloadResult(
        file: finalFile,
        driveFileId: driveFileId,
        manifest: inspected.manifest,
        sizeBytes: downloadedBytes,
        sha256Hex: actualSha,
      );
    } catch (_) {
      if (sink != null) {
        try {
          await sink.close();
        } catch (closeErr) {
          _log(
            '[ResumableDriveUploader] İndirme akışı kapatma uyarısı: ${closeErr.runtimeType}',
          );
        }
      }
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (delErr) {
          _log(
            '[ResumableDriveUploader] Bozuk .part dosyası silinemedi (${p.basename(partFile.path)}): ${delErr.runtimeType}',
          );
        }
      }
      rethrow;
    }
  }

  Future<String?> _findFolderIdOnly({
    required String name,
    String? parentId,
    BackupCancellationToken? cancellationToken,
  }) async {
    final q = "name = '${_escape(name)}' and mimeType = 'application/vnd.google-apps.folder' "
        "and trashed = false${parentId != null ? " and '${_escape(parentId)}' in parents" : ''}";
    final uri = _filesListEndpoint.replace(queryParameters: {
      'q': q,
      'fields': 'files(id,name)',
      'spaces': 'drive',
    });
    final resp = await _sendAuthenticated(
      (token) => httpClient
          .get(uri, headers: {'authorization': 'Bearer $token'})
          .timeout(requestTimeout),
      cancellationToken: cancellationToken,
    );
    if (resp.statusCode != 200) {
      throw _classifyHttpFailure(resp);
    }
    final files = _decodeJsonMap(resp.body)['files'];
    if (files is List && files.isNotEmpty) {
      final first = files.first;
      if (first is Map && first['id'] is String) {
        final id = first['id'] as String;
        if (id.isNotEmpty) return id;
      }
    }
    return null;
  }

  static HubDriveRemoteBackup? _tryParseHubRemoteBackup(
    Map<String, dynamic> raw, {
    required bool requireExplicitHubMarker,
  }) {
    final id = raw['id'] as String?;
    final name = raw['name'] as String?;
    if (id == null || id.isEmpty || name == null || !name.endsWith('.mmsbak')) {
      return null;
    }
    final propsRaw = raw['appProperties'];
    final props = propsRaw is Map
        ? Map<String, dynamic>.from(propsRaw)
        : const <String, dynamic>{};

    final rawDbType = props['mms_database_type']?.toString();
    if (rawDbType != null &&
        rawDbType.isNotEmpty &&
        rawDbType != DatabaseType.centralMaster.value) {
      return null;
    }

    final rawSource = props[MmsDriveBackupFolders.backupSourceProperty]?.toString();
    final isMarkedHub = rawSource == MmsDriveBackupFolders.hubBackupSource ||
        name.startsWith(MmsDriveBackupFolders.hubBackupFilePrefix);
    if (requireExplicitHubMarker && !isMarkedHub) {
      return null;
    }
    if (rawSource != null &&
        rawSource.isNotEmpty &&
        rawSource != MmsDriveBackupFolders.hubBackupSource) {
      return null;
    }

    String? backupId = props['mms_backup_id']?.toString();
    if (backupId == null || backupId.isEmpty) {
      if (name.startsWith(MmsDriveBackupFolders.hubBackupFilePrefix)) {
        backupId = name.substring(
          MmsDriveBackupFolders.hubBackupFilePrefix.length,
          name.length - '.mmsbak'.length,
        );
      }
    }
    final sizeRaw = raw['size'];
    final sizeBytes = sizeRaw is int
        ? sizeRaw
        : int.tryParse(sizeRaw?.toString() ?? '') ?? 0;
    final createdRaw = raw['createdTime'] as String?;
    return HubDriveRemoteBackup(
      driveFileId: id,
      fileName: name,
      backupId: (backupId != null && backupId.isNotEmpty) ? backupId : null,
      sizeBytes: sizeBytes,
      sha256Hex: (props['mms_sha256'] as String?)?.toLowerCase(),
      md5Hex: (raw['md5Checksum'] as String?)?.toLowerCase(),
      schemaVersion: int.tryParse(props['mms_schema_version']?.toString() ?? ''),
      hubId: props['mms_device_id'] as String?,
      createdTimeUtc:
          createdRaw != null ? DateTime.tryParse(createdRaw)?.toUtc() : null,
    );
  }

  static String _escape(String v) =>
      v.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  Future<http.StreamedResponse> _sendStreamAuthenticated(
    Future<http.StreamedResponse> Function(String token) op, {
    BackupCancellationToken? cancellationToken,
  }) async {
    Future<http.StreamedResponse> runOnce(String token) async {
      try {
        return await op(token);
      } on SocketException catch (e) {
        throw DriveResumableUploadException(
          kind: DriveUploadFailureKind.transient,
          code: 'RETRY_PENDING',
          message: 'Ağ hatası: ${e.message}',
        );
      } on TimeoutException {
        throw const DriveResumableUploadException(
          kind: DriveUploadFailureKind.transient,
          code: 'RETRY_PENDING',
          message: 'Google Drive indirme isteği zaman aşımına uğradı.',
        );
      } on http.ClientException catch (e) {
        throw DriveResumableUploadException(
          kind: DriveUploadFailureKind.transient,
          code: 'RETRY_PENDING',
          message: 'HTTP istemci hatası: ${e.message}',
        );
      }
    }

    var token = await _fetchAccessToken(
      forceRefresh: false,
      cancellationToken: cancellationToken,
    );
    var resp = await runOnce(token);
    if (resp.statusCode == 401) {
      await resp.stream.drain<void>();
      token = await _fetchAccessToken(
        forceRefresh: true,
        cancellationToken: cancellationToken,
      );
      resp = await runOnce(token);
    }
    return resp;
  }

  Future<http.Response> _sendAuthenticated(
    Future<http.Response> Function(String token) op, {
    BackupCancellationToken? cancellationToken,
    String? sessionUri,
    int uploadedBytes = 0,
  }) async {
    var token = await _fetchAccessToken(
      forceRefresh: false,
      cancellationToken: cancellationToken,
      sessionUri: sessionUri,
      uploadedBytes: uploadedBytes,
    );
    var resp = await _sendWithCancellation(
      () => op(token),
      cancellationToken: cancellationToken,
      sessionUri: sessionUri,
      uploadedBytes: uploadedBytes,
    );
    if (resp.statusCode == 401) {
      token = await _fetchAccessToken(
        forceRefresh: true,
        cancellationToken: cancellationToken,
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
      resp = await _sendWithCancellation(
        () => op(token),
        cancellationToken: cancellationToken,
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    }
    return resp;
  }

  Future<String> _fetchAccessToken({
    bool forceRefresh = false,
    BackupCancellationToken? cancellationToken,
    String? sessionUri,
    int uploadedBytes = 0,
  }) async {
    _throwIfCancelled(cancellationToken, sessionUri, uploadedBytes);
    try {
      return await accessTokenProvider(forceRefresh: forceRefresh);
    } on DriveResumableUploadException {
      rethrow;
    } on SocketException catch (e) {
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.transient,
        code: 'RETRY_PENDING',
        message: 'Google OAuth erişim ağı hatası: ${e.message}',
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    } on TimeoutException {
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.transient,
        code: 'RETRY_PENDING',
        message: 'Google OAuth erişim anahtarı isteği zaman aşımına uğradı.',
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    } on http.ClientException catch (e) {
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.transient,
        code: 'RETRY_PENDING',
        message: 'Google OAuth istemci hatası: ${e.message}',
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    } on DriveBackupException catch (e) {
      if (e.code == 'ERR_DRIVE_UNAVAILABLE') {
        throw DriveResumableUploadException(
          kind: DriveUploadFailureKind.transient,
          code: 'RETRY_PENDING',
          message: e.message,
          sessionUri: sessionUri,
          uploadedBytes: uploadedBytes,
        );
      }
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.authFailure,
        code: 'FAILED_AUTH',
        message: e.message,
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    } catch (e) {
      final raw = e.toString();
      if (raw.contains('ERR_OAUTH_REFRESH_UNAVAILABLE')) {
        throw DriveResumableUploadException(
          kind: DriveUploadFailureKind.transient,
          code: 'RETRY_PENDING',
          message: 'Google Drive OAuth token yenilemesi geçici olarak başarısız: $raw',
          sessionUri: sessionUri,
          uploadedBytes: uploadedBytes,
        );
      }
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.authFailure,
        code: 'FAILED_AUTH',
        message: 'Google Drive erişim anahtarı alınamadı: $e',
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    }
  }

  Future<String> _ensureFolder({
    BackupCancellationToken? cancellationToken,
    String? sessionUri,
    int uploadedBytes = 0,
  }) async {
    final rootId = await _findOrCreateFolder(
      name: folderName,
      cancellationToken: cancellationToken,
      sessionUri: sessionUri,
      uploadedBytes: uploadedBytes,
    );
    final sub = subfolderName;
    if (sub == null || sub.isEmpty) return rootId;
    return _findOrCreateFolder(
      name: sub,
      parentId: rootId,
      cancellationToken: cancellationToken,
      sessionUri: sessionUri,
      uploadedBytes: uploadedBytes,
    );
  }

  Future<String> _findOrCreateFolder({
    required String name,
    String? parentId,
    BackupCancellationToken? cancellationToken,
    String? sessionUri,
    int uploadedBytes = 0,
  }) async {
    String esc(String v) => v.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final q = "name = '${esc(name)}' and mimeType = 'application/vnd.google-apps.folder' "
        "and trashed = false${parentId != null ? " and '${esc(parentId)}' in parents" : ''}";
    final searchUri = _filesListEndpoint.replace(queryParameters: {
      'q': q,
      'fields': 'files(id,name)',
      'spaces': 'drive',
    });
    final listResp = await _sendAuthenticated(
      (token) => httpClient
          .get(searchUri, headers: {'authorization': 'Bearer $token'})
          .timeout(requestTimeout),
      cancellationToken: cancellationToken,
      sessionUri: sessionUri,
      uploadedBytes: uploadedBytes,
    );
    if (listResp.statusCode != 200) {
      throw _classifyHttpFailure(
        listResp,
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    }
    final listBody = _decodeJsonMap(listResp.body);
    final files = listBody['files'];
    if (files is List && files.isNotEmpty) {
      final first = files.first;
      if (first is Map && first['id'] is String) {
        return first['id'] as String;
      }
    }

    final createResp = await _sendAuthenticated(
      (token) => httpClient
          .post(
            _filesListEndpoint,
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'name': name,
              'mimeType': 'application/vnd.google-apps.folder',
              if (parentId != null) 'parents': [parentId],
            }),
          )
          .timeout(requestTimeout),
      cancellationToken: cancellationToken,
      sessionUri: sessionUri,
      uploadedBytes: uploadedBytes,
    );
    if (createResp.statusCode != 200 && createResp.statusCode != 201) {
      throw _classifyHttpFailure(
        createResp,
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    }
    final created = _decodeJsonMap(createResp.body);
    final id = created['id'];
    if (id is! String || id.isEmpty) {
      throw const DriveResumableUploadException(
        kind: DriveUploadFailureKind.transient,
        code: 'ERR_DRIVE_FOLDER_CREATE',
        message: 'Google Drive yedek klasörü id döndürmedi.',
      );
    }
    return id;
  }

  Future<String> _initiateResumableSession({
    required String folderId,
    required String fileName,
    required int totalBytes,
    required BackupManifest manifest,
    required String encryptedSha256,
    BackupCancellationToken? cancellationToken,
  }) async {
    final resp = await _sendAuthenticated(
      (token) => httpClient
          .post(
            _resumableInitEndpoint,
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json; charset=UTF-8',
              'x-upload-content-type': 'application/octet-stream',
              'x-upload-content-length': totalBytes.toString(),
            },
            body: jsonEncode({
              'name': fileName,
              'parents': [folderId],
              'appProperties': {
                ...extraAppProperties,
                'mms_backup_id': manifest.backupId,
                'mms_sha256': encryptedSha256,
                'mms_schema_version': manifest.schemaVersion.toString(),
                'mms_device_id': manifest.deviceId,
              },
            }),
          )
          .timeout(requestTimeout),
      cancellationToken: cancellationToken,
      sessionUri: null,
      uploadedBytes: 0,
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw _classifyHttpFailure(resp);
    }
    final location = resp.headers['location'];
    if (location == null || location.isEmpty) {
      throw const DriveResumableUploadException(
        kind: DriveUploadFailureKind.transient,
        code: 'ERR_DRIVE_MISSING_SESSION_URI',
        message: 'Google Drive resumable oturum Location başlığı döndürmedi.',
      );
    }
    return location;
  }

  Future<({bool expired, int nextOffset, String? completedFileId, bool completedMissingId})>
      _probeSessionOffset({
    required String sessionUri,
    required int totalBytes,
    BackupCancellationToken? cancellationToken,
  }) async {
    final resp = await _sendAuthenticated(
      (token) => httpClient
          .put(
            Uri.parse(sessionUri),
            headers: {
              'authorization': 'Bearer $token',
              'content-length': '0',
              'content-range': 'bytes */$totalBytes',
            },
          )
          .timeout(requestTimeout),
      cancellationToken: cancellationToken,
      sessionUri: sessionUri,
      uploadedBytes: 0,
    );
    if (resp.statusCode == 404 || resp.statusCode == 410) {
      return (
        expired: true,
        nextOffset: 0,
        completedFileId: null,
        completedMissingId: false,
      );
    }
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      final decoded = _decodeJsonMap(resp.body);
      final rawId = decoded['id'];
      final id = rawId is String && rawId.isNotEmpty ? rawId : null;
      return (
        expired: false,
        nextOffset: totalBytes,
        completedFileId: id,
        completedMissingId: id == null,
      );
    }
    if (resp.statusCode == 308) {
      final next = _parseRangeNextOffset(resp.headers['range']) ?? 0;
      return (
        expired: false,
        nextOffset: next,
        completedFileId: null,
        completedMissingId: false,
      );
    }
    throw _classifyHttpFailure(resp, sessionUri: sessionUri, uploadedBytes: 0);
  }

  Future<String?> _findOrCleanupExistingRemoteFile({
    required String folderId,
    required String expectedBackupId,
    required int expectedSizeBytes,
    required String expectedSha256Hex,
    required String expectedMd5Hex,
    BackupCancellationToken? cancellationToken,
    String? sessionUri,
  }) async {
    String esc(String v) => v.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final q = "'${esc(folderId)}' in parents and "
        "appProperties has { key='mms_backup_id' and value = '${esc(expectedBackupId)}' } "
        "and trashed = false";
    final searchUri = _filesListEndpoint.replace(queryParameters: {
      'q': q,
      'fields': 'files(id,name,size,md5Checksum,appProperties)',
      'spaces': 'drive',
    });
    final resp = await _sendAuthenticated(
      (token) => httpClient
          .get(searchUri, headers: {'authorization': 'Bearer $token'})
          .timeout(requestTimeout),
      cancellationToken: cancellationToken,
      sessionUri: sessionUri,
      uploadedBytes: expectedSizeBytes,
    );
    if (resp.statusCode != 200) {
      return null;
    }
    final files = (_decodeJsonMap(resp.body)['files'] as List?) ?? const [];
    for (final raw in files) {
      if (raw is! Map) continue;
      final id = raw['id'] as String?;
      if (id == null || id.isEmpty) continue;
      if (_matchesExpectedRemoteMeta(
        Map<String, dynamic>.from(raw),
        expectedBackupId: expectedBackupId,
        expectedSizeBytes: expectedSizeBytes,
        expectedSha256Hex: expectedSha256Hex,
        expectedMd5Hex: expectedMd5Hex,
      )) {
        return id;
      }
      await _tryDeleteCorruptedRemoteFile(fileId: id);
    }
    return null;
  }

  static bool _matchesExpectedRemoteMeta(
    Map<String, dynamic> body, {
    required String expectedBackupId,
    required int expectedSizeBytes,
    required String expectedSha256Hex,
    required String expectedMd5Hex,
  }) {
    final sizeRaw = body['size'];
    final remoteSize = sizeRaw is int
        ? sizeRaw
        : int.tryParse(sizeRaw?.toString() ?? '');
    if (remoteSize != expectedSizeBytes) return false;

    final remoteMd5 = (body['md5Checksum'] as String?)?.toLowerCase();
    if (remoteMd5 != null && remoteMd5.isNotEmpty && remoteMd5 != expectedMd5Hex) {
      return false;
    }
    final appProps = body['appProperties'];
    if (appProps is Map) {
      final remoteBackupId = appProps['mms_backup_id']?.toString();
      final remoteSha = appProps['mms_sha256']?.toString().toLowerCase();
      if (remoteBackupId != null && remoteBackupId != expectedBackupId) {
        return false;
      }
      if (remoteSha != null && remoteSha != expectedSha256Hex) {
        return false;
      }
    }
    return true;
  }

  Future<void> _tryDeleteCorruptedRemoteFile({
    required String fileId,
  }) async {
    try {
      await _sendAuthenticated(
        (token) => httpClient
            .delete(
              Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId'),
              headers: {'authorization': 'Bearer $token'},
            )
            .timeout(requestTimeout),
      );
    } catch (e) {
      // Best-effort temizlik: ana doğrulama hatası her durumda fırlatılır.
      _log(
        '[ResumableDriveUploader] Bozuk uzak dosya silme temizliği başarısız ($fileId): ${e.runtimeType}',
      );
    }
  }

  Future<void> _verifyRemoteFile({
    required String fileId,
    required String expectedBackupId,
    required int expectedSizeBytes,
    required String expectedSha256Hex,
    required String expectedMd5Hex,
    BackupCancellationToken? cancellationToken,
    String? sessionUri,
  }) async {
    final uri = Uri.parse(
      'https://www.googleapis.com/drive/v3/files/$fileId?fields=id,name,size,md5Checksum,appProperties',
    );
    final resp = await _sendAuthenticated(
      (token) => httpClient
          .get(uri, headers: {'authorization': 'Bearer $token'})
          .timeout(requestTimeout),
      cancellationToken: cancellationToken,
      sessionUri: sessionUri,
      uploadedBytes: expectedSizeBytes,
    );
    if (resp.statusCode != 200) {
      throw _classifyHttpFailure(
        resp,
        sessionUri: sessionUri,
        uploadedBytes: expectedSizeBytes,
      );
    }

    final body = _decodeJsonMap(resp.body);
    final sizeRaw = body['size'];
    final remoteSize = sizeRaw is int
        ? sizeRaw
        : int.tryParse(sizeRaw?.toString() ?? '');
    if (remoteSize != expectedSizeBytes) {
      await _tryDeleteCorruptedRemoteFile(fileId: fileId);
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.integrityVerificationFailed,
        code: 'ERR_DRIVE_VERIFY_SIZE_MISMATCH',
        message:
            'Drive doğrulama boyutu uyuşmuyor ($remoteSize != $expectedSizeBytes).',
        statusCode: resp.statusCode,
        sessionUri: sessionUri,
        uploadedBytes: expectedSizeBytes,
      );
    }

    final remoteMd5 = (body['md5Checksum'] as String?)?.toLowerCase();
    if (remoteMd5 != null && remoteMd5.isNotEmpty && remoteMd5 != expectedMd5Hex) {
      await _tryDeleteCorruptedRemoteFile(fileId: fileId);
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.integrityVerificationFailed,
        code: 'ERR_DRIVE_VERIFY_MD5_MISMATCH',
        message: 'Drive doğrulama MD5 özeti uyuşmuyor ($remoteMd5 != $expectedMd5Hex).',
        statusCode: resp.statusCode,
        sessionUri: sessionUri,
        uploadedBytes: expectedSizeBytes,
      );
    }

    final appProps = body['appProperties'];
    if (appProps is Map) {
      final remoteBackupId = appProps['mms_backup_id']?.toString();
      final remoteSha = appProps['mms_sha256']?.toString().toLowerCase();
      if (remoteBackupId != null && remoteBackupId != expectedBackupId) {
        await _tryDeleteCorruptedRemoteFile(fileId: fileId);
        throw const DriveResumableUploadException(
          kind: DriveUploadFailureKind.integrityVerificationFailed,
          code: 'ERR_DRIVE_VERIFY_BACKUP_ID_MISMATCH',
          message: 'Drive dosya appProperties.mms_backup_id eşleşmiyor.',
        );
      }
      if (remoteSha != null && remoteSha != expectedSha256Hex) {
        await _tryDeleteCorruptedRemoteFile(fileId: fileId);
        throw const DriveResumableUploadException(
          kind: DriveUploadFailureKind.integrityVerificationFailed,
          code: 'ERR_DRIVE_VERIFY_SHA_MISMATCH',
          message: 'Drive dosya appProperties.mms_sha256 eşleşmiyor.',
        );
      }
    }
  }

  DriveResumableUploadException _classifyHttpFailure(
    http.Response resp, {
    String? sessionUri,
    int uploadedBytes = 0,
  }) {
    final code = resp.statusCode;
    final lowerBody = resp.body.toLowerCase();
    if (code == 403 &&
        (lowerBody.contains('storagequotaexceeded') ||
            lowerBody.contains('quotaexceeded') ||
            lowerBody.contains('teamdrivefilelimitexceeded'))) {
      return DriveResumableUploadException(
        kind: DriveUploadFailureKind.quotaExceeded,
        code: 'FAILED_QUOTA',
        message: 'Google Drive depolama kotası dolu; lütfen Drive alanını temizleyin.',
        statusCode: code,
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    }
    if (code == 401 || code == 403) {
      return DriveResumableUploadException(
        kind: DriveUploadFailureKind.authFailure,
        code: 'FAILED_AUTH',
        message:
            'Google Drive kimlik doğrulama veya kapsam yetkisi reddedildi (HTTP $code). Hesabı yeniden bağlayın.',
        statusCode: code,
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    }
    return DriveResumableUploadException(
      kind: DriveUploadFailureKind.transient,
      code: 'RETRY_PENDING',
      message: 'Google Drive yüklemesi geçici hata aldı (HTTP $code).',
      statusCode: code,
      sessionUri: sessionUri,
      uploadedBytes: uploadedBytes,
    );
  }

  Future<http.Response> _sendWithCancellation(
    Future<http.Response> Function() op, {
    BackupCancellationToken? cancellationToken,
    String? sessionUri,
    int uploadedBytes = 0,
  }) async {
    _throwIfCancelled(cancellationToken, sessionUri, uploadedBytes);
    final reqFuture = op();
    if (cancellationToken == null) {
      try {
        return await reqFuture;
      } on SocketException catch (e) {
        throw DriveResumableUploadException(
          kind: DriveUploadFailureKind.transient,
          code: 'RETRY_PENDING',
          message: 'Ağ hatası: ${e.message}',
          sessionUri: sessionUri,
          uploadedBytes: uploadedBytes,
        );
      } on TimeoutException {
        throw DriveResumableUploadException(
          kind: DriveUploadFailureKind.transient,
          code: 'RETRY_PENDING',
          message: 'Google Drive isteği zaman aşımına uğradı.',
          sessionUri: sessionUri,
          uploadedBytes: uploadedBytes,
        );
      } on http.ClientException catch (e) {
        throw DriveResumableUploadException(
          kind: DriveUploadFailureKind.transient,
          code: 'RETRY_PENDING',
          message: 'HTTP istemci hatası: ${e.message}',
          sessionUri: sessionUri,
          uploadedBytes: uploadedBytes,
        );
      }
    }

    try {
      final result = await Future.any<http.Response?>([
        reqFuture,
        cancellationToken.onCancelled.then((_) => null),
      ]);
      if (result == null || cancellationToken.isCancelled) {
        // Arka planda kapanmayan istek hata fırlatırsa unhandled error olmasını önle.
        unawaited(reqFuture.then((_) {}, onError: (_) {}));
        throw DriveResumableUploadException(
          kind: DriveUploadFailureKind.cancelled,
          code: 'UPLOAD_CANCELLED_FOR_SHUTDOWN',
          message: 'Drive yüklemesi kapanış/iptal nedeniyle güvenle duraklatıldı.',
          sessionUri: sessionUri,
          uploadedBytes: uploadedBytes,
        );
      }
      return result;
    } on SocketException catch (e) {
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.transient,
        code: 'RETRY_PENDING',
        message: 'Ağ hatası: ${e.message}',
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    } on TimeoutException {
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.transient,
        code: 'RETRY_PENDING',
        message: 'Google Drive isteği zaman aşımına uğradı.',
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    } on http.ClientException catch (e) {
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.transient,
        code: 'RETRY_PENDING',
        message: 'HTTP istemci hatası: ${e.message}',
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    }
  }

  void _throwIfCancelled(
    BackupCancellationToken? token,
    String? sessionUri,
    int uploadedBytes,
  ) {
    if (token != null && token.isCancelled) {
      throw DriveResumableUploadException(
        kind: DriveUploadFailureKind.cancelled,
        code: 'UPLOAD_CANCELLED_FOR_SHUTDOWN',
        message: 'Drive yüklemesi iptal edildi.',
        sessionUri: sessionUri,
        uploadedBytes: uploadedBytes,
      );
    }
  }

  static int? _parseRangeNextOffset(String? rangeHeader) {
    if (rangeHeader == null || rangeHeader.isEmpty) return null;
    final match = RegExp(r'bytes=0-(\d+)').firstMatch(rangeHeader);
    if (match == null) return null;
    final end = int.tryParse(match.group(1)!);
    return end == null ? null : end + 1;
  }

  static Future<int> _readExactInto(
    RandomAccessFile raf,
    List<int> buffer,
    int length,
  ) async {
    var offset = 0;
    while (offset < length) {
      final read = await raf.readInto(buffer, offset, length);
      if (read <= 0) break;
      offset += read;
    }
    return offset;
  }

  static Future<({String sha256Hex, String md5Hex})> _computeFileSha256AndMd5(
    File file,
  ) async {
    final md5DigestSink = _SingleMd5Sink();
    final md5Hasher = md5.startChunkedConversion(md5DigestSink);
    final shaDigest = await sha256.bind(file.openRead().map((chunk) {
      md5Hasher.add(chunk);
      return chunk;
    })).first;
    md5Hasher.close();
    return (
      sha256Hex: shaDigest.toString().toLowerCase(),
      md5Hex: md5DigestSink.digest.toString().toLowerCase(),
    );
  }

  static Map<String, dynamic> _decodeJsonMap(
    String body, {
    void Function(String message)? log,
  }) {
    if (body.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      (log ?? _defaultLog)(
        '[ResumableDriveUploader] Drive JSON yanıtı ayrıştırılamadı: ${e.runtimeType}',
      );
    }
    return const {};
  }
}
