import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../domain/app_update_info.dart';

/// Güvenli indirme, SHA-256 doğrulama veya yerel kurulum başlatma hatası.
class AppUpdateInstallException implements Exception {
  final String code;
  final String message;

  const AppUpdateInstallException(this.code, this.message);

  @override
  String toString() => 'AppUpdateInstallException($code): $message';
}

/// Güncelleme paketini HTTPS üzerinden indirip SHA-256 özetini doğrulayan ve
/// yalnızca doğrulama başarılı olursa platform kurulumunu başlatan servis.
///
/// Fail-closed: SHA-256 doğrulaması başarısız olursa indirilen dosya diskten
/// derhal silinir ve kurulum kesinlikle başlatılmaz.
class AppUpdateInstaller {
  static const String channelName = 'com.marketmms.market_pos/app_updater';

  final http.Client? client;
  final Directory? downloadDirectory;
  final MethodChannel? androidChannel;
  final Future<void> Function(String filePath)? windowsLauncher;
  final void Function(int exitCode)? exitProcess;
  final TargetPlatform? platformOverride;
  final Duration timeout;

  const AppUpdateInstaller({
    this.client,
    this.downloadDirectory,
    this.androidChannel,
    this.windowsLauncher,
    this.exitProcess,
    this.platformOverride,
    this.timeout = const Duration(minutes: 5),
  });

  TargetPlatform get _platform => platformOverride ?? defaultTargetPlatform;

  MethodChannel get _channel =>
      androidChannel ?? const MethodChannel(channelName);

  /// Paketi HTTPS üzerinden indirir, SHA-256 özetini sabit zamanlı olarak
  /// [manifest.sha256Checksum] ile karşılaştırır ve doğrulanmış dosyayı döner.
  Future<File> downloadAndVerify(
    AppUpdateManifest manifest, {
    void Function(double progress)? onProgress,
  }) async {
    final problem = manifest.integrityProblem;
    if (problem != null ||
        manifest.downloadUrl == null ||
        manifest.sha256Checksum == null) {
      throw AppUpdateInstallException(
        'INVALID_MANIFEST',
        problem ?? 'İndirme adresi veya SHA-256 doğrulama özeti eksik.',
      );
    }

    final downloadUri = Uri.tryParse(manifest.downloadUrl!);
    if (downloadUri == null ||
        downloadUri.scheme != 'https' ||
        downloadUri.host.isEmpty) {
      throw const AppUpdateInstallException(
        'INVALID_MANIFEST',
        'İndirme adresi HTTPS değil; güvenli indirme reddedildi.',
      );
    }

    final targetDir = await _resolveDownloadDirectory();
    await targetDir.create(recursive: true);

    final fileName = _sanitizeFileName(
      manifest.assetFileName ??
          (downloadUri.pathSegments.isNotEmpty
              ? downloadUri.pathSegments.last
              : null),
    );
    final finalFile = File(p.join(targetDir.path, fileName));
    final partFile = File('${finalFile.path}.part');

    if (await partFile.exists()) {
      await partFile.delete();
    }

    final ownsClient = client == null;
    final activeClient = client ?? http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', downloadUri)
        ..headers['User-Agent'] = 'MarketMMS';
      final response = await activeClient.send(request).timeout(timeout);
      if (response.statusCode != 200) {
        throw AppUpdateInstallException(
          'HTTP_${response.statusCode}',
          'Güncelleme dosyası indirilemedi (HTTP ${response.statusCode}).',
        );
      }

      final totalBytes = response.contentLength ?? -1;
      var receivedBytes = 0;
      onProgress?.call(0.0);

      sink = partFile.openWrite();
      await for (final chunk in response.stream.timeout(timeout)) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call((receivedBytes / totalBytes).clamp(0.0, 0.99));
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final digest = await sha256.bind(partFile.openRead()).first;
      final actualSha = digest.toString().toLowerCase();
      final expectedSha = manifest.sha256Checksum!.trim().toLowerCase();

      if (!_constantTimeEqualsAscii(actualSha, expectedSha)) {
        await _safeDelete(partFile);
        await _safeDelete(finalFile);
        throw const AppUpdateInstallException(
          'SHA256_MISMATCH',
          'İndirilen dosyanın SHA-256 bütünlük doğrulaması başarısız oldu; dosya güvenlik gereği silindi.',
        );
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      final verified = await partFile.rename(finalFile.path);
      onProgress?.call(1.0);
      return verified;
    } catch (e) {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      await _safeDelete(partFile);
      if (e is AppUpdateInstallException) rethrow;
      throw AppUpdateInstallException(
        'DOWNLOAD_FAILED',
        'Güncelleme indirilirken hata oluştu: $e',
      );
    } finally {
      if (ownsClient) {
        activeClient.close();
      }
    }
  }

  /// Doğrulanmış paketin platform kurulumunu başlatır.
  Future<void> installVerifiedFile(File verifiedFile) async {
    if (!await verifiedFile.exists()) {
      throw const AppUpdateInstallException(
        'FILE_NOT_FOUND',
        'Kurulacak doğrulanmış güncelleme dosyası bulunamadı.',
      );
    }

    switch (_platform) {
      case TargetPlatform.windows:
        if (windowsLauncher != null) {
          await windowsLauncher!(verifiedFile.path);
        } else {
          await Process.start(
            'msiexec',
            ['/i', verifiedFile.path],
            mode: ProcessStartMode.detached,
          );
        }
        (exitProcess ?? exit)(0);
        return;
      case TargetPlatform.android:
        await _channel.invokeMethod<void>(
          'installApk',
          {'filePath': verifiedFile.path},
        );
        return;
      default:
        throw const AppUpdateInstallException(
          'UNSUPPORTED_PLATFORM',
          'Bu platformda otomatik kurulum başlatma desteklenmiyor.',
        );
    }
  }

  /// Paket indirme, SHA-256 doğrulama ve platform kurulum adımlarını uçtan uca
  /// yürütür.
  Future<void> downloadVerifyAndInstall(
    AppUpdateManifest manifest, {
    void Function(double progress)? onProgress,
  }) async {
    final verified = await downloadAndVerify(manifest, onProgress: onProgress);
    await installVerifiedFile(verified);
  }

  Future<Directory> _resolveDownloadDirectory() async {
    final customDir = downloadDirectory;
    if (customDir != null) return customDir;

    if (_platform == TargetPlatform.android) {
      try {
        final cachePath =
            await _channel.invokeMethod<String>('getUpdateCacheDir');
        if (cachePath != null && cachePath.trim().isNotEmpty) {
          return Directory(cachePath.trim());
        }
      } on MissingPluginException {
        // Test veya Android dışı bağlamlarda systemTemp geri dönüşü.
      }
    }

    return Directory(p.join(Directory.systemTemp.path, 'MarketMMS_Updates'));
  }

  String _sanitizeFileName(String? rawName) {
    final trimmed = rawName?.trim() ?? '';
    final base = p.basename(trimmed);
    final sanitized = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (sanitized.isEmpty ||
        sanitized == '.' ||
        sanitized == '..' ||
        sanitized.endsWith('.part')) {
      return _platform == TargetPlatform.android
          ? 'MarketMMS-update.apk'
          : 'MarketMMS-update.msi';
    }
    return sanitized;
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static bool _constantTimeEqualsAscii(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
