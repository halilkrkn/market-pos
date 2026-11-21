package com.marketmms.market_pos

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/// ADR-020: Android sistem düzeyi periyodik arka plan yedekleme zamanlayıcı kanalı ve JobService.
///
/// Uygulama kapalıyken ve cihaz yeniden başlatıldığında `JobScheduler` (`setPersisted(true)`)
/// aracılığıyla arka plan `FlutterEngine` başlatır, Android Keystore (`MmsSecureStorageChannelHandler`)
/// kanalını ortak kaydeder ve `mmsBackgroundBackupEntrypoint` Dart giriş noktasını çalıştırır.
class MmsBackgroundBackupChannelHandler(private val appContext: Context) {
    companion object {
        const val CHANNEL_NAME = "com.marketmms.market_pos/background_backup"
        const val PREFS_NAME = "market_mms_bg_backup_prefs"
        const val JOB_ID = 70201
        private const val MIN_INTERVAL_MINUTES = 15L
    }

    fun registerWith(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "schedulePeriodicBackup" -> {
                        val intervalMinutes = (call.argument<Number>("intervalMinutes")?.toLong() ?: 360L)
                            .coerceAtLeast(MIN_INTERVAL_MINUTES)
                        val requiresNetwork = call.argument<Boolean>("requiresNetwork") ?: false
                        val requiresBatteryNotLow = call.argument<Boolean>("requiresBatteryNotLow") ?: true
                        val requiresStorageNotLow = call.argument<Boolean>("requiresStorageNotLow") ?: true

                        val status = scheduleJob(
                            intervalMinutes = intervalMinutes,
                            requiresNetwork = requiresNetwork,
                            requiresBatteryNotLow = requiresBatteryNotLow,
                            requiresStorageNotLow = requiresStorageNotLow,
                        )
                        result.success(status)
                    }
                    "cancelPeriodicBackup" -> {
                        cancelJob()
                        result.success(readStatusMap())
                    }
                    "getScheduleStatus" -> {
                        result.success(readStatusMap())
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("BACKGROUND_BACKUP_ERROR", e.localizedMessage ?: "Arka plan yedek zamanlama hatası.", null)
            }
        }
    }

    private fun scheduleJob(
        intervalMinutes: Long,
        requiresNetwork: Boolean,
        requiresBatteryNotLow: Boolean,
        requiresStorageNotLow: Boolean,
    ): Map<String, Any?> {
        val scheduler = appContext.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
        val component = ComponentName(appContext, MmsBackgroundBackupJobService::class.java)
        val intervalMs = intervalMinutes * 60_000L

        val builder = JobInfo.Builder(JOB_ID, component)
            .setPeriodic(intervalMs)
            .setPersisted(true)
            .setBackoffCriteria(5 * 60_000L, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
            .setRequiredNetworkType(
                if (requiresNetwork) JobInfo.NETWORK_TYPE_ANY else JobInfo.NETWORK_TYPE_NONE,
            )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setRequiresBatteryNotLow(requiresBatteryNotLow)
            builder.setRequiresStorageNotLow(requiresStorageNotLow)
        }

        val scheduledCode = scheduler.schedule(builder.build())
        if (scheduledCode != JobScheduler.RESULT_SUCCESS) {
            throw IllegalStateException("Android JobScheduler zamanlaması reddedildi ($scheduledCode).")
        }

        val nextRunMs = System.currentTimeMillis() + intervalMs
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean("isScheduled", true)
            .putLong("intervalMinutes", intervalMinutes)
            .putBoolean("requiresNetwork", requiresNetwork)
            .putBoolean("requiresBatteryNotLow", requiresBatteryNotLow)
            .putBoolean("requiresStorageNotLow", requiresStorageNotLow)
            .putLong("nextRunEpochMs", nextRunMs)
            .apply()

        return readStatusMap()
    }

    private fun cancelJob() {
        val scheduler = appContext.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
        scheduler.cancel(JOB_ID)
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean("isScheduled", false)
            .remove("nextRunEpochMs")
            .apply()
    }

    private fun readStatusMap(): Map<String, Any?> {
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val scheduler = appContext.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
        val systemPending = scheduler.allPendingJobs.any { it.id == JOB_ID }
        val isScheduled = prefs.getBoolean("isScheduled", false) && systemPending
        return hashMapOf(
            "isScheduled" to isScheduled,
            "intervalMinutes" to prefs.getLong("intervalMinutes", 360L),
            "requiresNetwork" to prefs.getBoolean("requiresNetwork", false),
            "requiresBatteryNotLow" to prefs.getBoolean("requiresBatteryNotLow", true),
            "requiresStorageNotLow" to prefs.getBoolean("requiresStorageNotLow", true),
            "lastRunEpochMs" to if (prefs.contains("lastRunEpochMs")) prefs.getLong("lastRunEpochMs", 0L) else null,
            "lastStatus" to prefs.getString("lastStatus", null),
            "lastErrorCode" to prefs.getString("lastErrorCode", null),
            "nextRunEpochMs" to if (prefs.contains("nextRunEpochMs")) prefs.getLong("nextRunEpochMs", 0L) else null,
        )
    }
}

class MmsBackgroundBackupJobService : JobService() {
    companion object {
        private const val WORKER_CHANNEL = "com.marketmms.market_pos/background_backup_worker"
        private const val DART_ENTRYPOINT = "mmsBackgroundBackupEntrypoint"
        private const val WORKER_TIMEOUT_MS = 120_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var activeEngine: FlutterEngine? = null
    private var timeoutRunnable: Runnable? = null

    override fun onStartJob(params: JobParameters): Boolean {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)

        val engine = FlutterEngine(applicationContext)
        activeEngine = engine

        // ADR-020: Arka plan motoruna da Keystore güvenli depo kanalını kaydet
        MmsSecureStorageChannelHandler(applicationContext).registerWith(engine)
        MmsBackgroundBackupChannelHandler(applicationContext).registerWith(engine)

        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            WORKER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "completeBackgroundWork") {
                val success = call.argument<Boolean>("success") ?: false
                val status = call.argument<String>("status") ?: if (success) "SUCCESS" else "FAILED"
                val errorCode = call.argument<String>("errorCode")
                val shouldRetry = call.argument<Boolean>("shouldRetry") ?: !success
                recordRunOutcome(status = status, errorCode = errorCode)
                result.success(null)
                finishAndDestroy(params, needsReschedule = shouldRetry)
            } else {
                result.notImplemented()
            }
        }

        val timeout = Runnable {
            recordRunOutcome(status = "TIMEOUT", errorCode = "ERR_BG_WORKER_TIMEOUT")
            finishAndDestroy(params, needsReschedule = true)
        }
        timeoutRunnable = timeout
        mainHandler.postDelayed(timeout, WORKER_TIMEOUT_MS)

        val entrypoint = DartExecutor.DartEntrypoint(loader.findAppBundlePath(), DART_ENTRYPOINT)
        engine.dartExecutor.executeDartEntrypoint(entrypoint)
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        recordRunOutcome(status = "STOPPED_BY_OS", errorCode = "ERR_BG_OS_STOPPED")
        destroyEngine()
        return true // OS kesintisinde backoff ile tekrar dene
    }

    private fun recordRunOutcome(status: String, errorCode: String?) {
        val prefs = applicationContext.getSharedPreferences(
            MmsBackgroundBackupChannelHandler.PREFS_NAME,
            Context.MODE_PRIVATE,
        )
        val intervalMs = prefs.getLong("intervalMinutes", 360L) * 60_000L
        val now = System.currentTimeMillis()
        prefs.edit()
            .putLong("lastRunEpochMs", now)
            .putString("lastStatus", status)
            .putString("lastErrorCode", errorCode)
            .putLong("nextRunEpochMs", now + intervalMs)
            .apply()
    }

    private fun finishAndDestroy(params: JobParameters, needsReschedule: Boolean) {
        timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        timeoutRunnable = null
        mainHandler.post {
            destroyEngine()
            jobFinished(params, needsReschedule)
        }
    }

    private fun destroyEngine() {
        timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        timeoutRunnable = null
        activeEngine?.destroy()
        activeEngine = null
    }
}
