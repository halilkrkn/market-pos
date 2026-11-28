package com.marketmms.market_pos

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Doğrulanmış Market MMS Android APK güncellemeleri için cache dizini ve
/// FileProvider üzerinden sistem paket kurucu Intent köprüsü.
class MmsAppUpdaterChannelHandler(private val appContext: Context) {
    companion object {
        const val CHANNEL_NAME = "com.marketmms.market_pos/app_updater"
        private const val UPDATES_SUBDIR = "MarketMMS_Updates"
    }

    fun registerWith(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getUpdateCacheDir" -> {
                        val updatesDir = File(appContext.cacheDir, UPDATES_SUBDIR).apply {
                            if (!exists()) mkdirs()
                        }
                        result.success(updatesDir.absolutePath)
                    }
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")?.trim()
                        if (filePath.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "filePath zorunludur.", null)
                            return@setMethodCallHandler
                        }
                        launchApkInstaller(filePath)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error(
                    "APP_UPDATER_ERROR",
                    e.localizedMessage ?: "APK kurulumu başlatılamadı.",
                    null,
                )
            }
        }
    }

    private fun launchApkInstaller(filePath: String) {
        val allowedRoot = File(appContext.cacheDir, UPDATES_SUBDIR).canonicalFile
        val apkFile = File(filePath).canonicalFile
        if (!apkFile.exists() || !apkFile.isFile) {
            throw IllegalArgumentException("APK dosyası bulunamadı.")
        }
        val rootPath = allowedRoot.path.let {
            if (it.endsWith(File.separator)) it else "$it${File.separator}"
        }
        if (!apkFile.path.startsWith(rootPath) ||
            !apkFile.name.endsWith(".apk", ignoreCase = true)
        ) {
            throw SecurityException("Yalnızca doğrulama önbelleğindeki APK dosyaları kurulabilir.")
        }

        val uri = FileProvider.getUriForFile(
            appContext,
            "${appContext.packageName}.fileprovider",
            apkFile,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        appContext.startActivity(intent)
    }
}
