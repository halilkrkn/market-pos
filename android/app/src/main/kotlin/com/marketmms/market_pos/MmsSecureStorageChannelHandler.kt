package com.marketmms.market_pos

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/// ADR-020: Ön plan Activity motoru VE arka plan BackupService motoru
/// tarafından ortaklaşa kaydedilen Android Keystore AES-256-GCM kanal yöneticisi.
class MmsSecureStorageChannelHandler(private val appContext: Context) {
    companion object {
        const val CHANNEL_NAME = "com.marketmms.market_pos/secure_storage"
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        private const val KEY_ALIAS = "market_mms_master_key_v1"
        private const val PREFS_NAME = "market_mms_secure_prefs"
        private const val AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_IV_LENGTH = 12
        private const val GCM_TAG_BITS = 128
    }

    fun registerWith(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                result.error(
                    "UNSUPPORTED_SDK",
                    "Android Keystore AES-GCM için Android 6.0 (API 23) veya üzeri gerekir.",
                    null,
                )
                return@setMethodCallHandler
            }

            try {
                when (call.method) {
                    "saveSecret" -> {
                        val key = call.argument<String>("key")
                        val value = call.argument<String>("value")
                        if (key.isNullOrEmpty() || value == null) {
                            result.error("INVALID_ARGS", "key ve value zorunludur.", null)
                            return@setMethodCallHandler
                        }
                        saveEncryptedSecret(key, value)
                        result.success(null)
                    }
                    "readSecret" -> {
                        val key = call.argument<String>("key")
                        if (key.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "key zorunludur.", null)
                            return@setMethodCallHandler
                        }
                        result.success(readEncryptedSecret(key))
                    }
                    "deleteSecret" -> {
                        val key = call.argument<String>("key")
                        if (key.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "key zorunludur.", null)
                            return@setMethodCallHandler
                        }
                        deleteEncryptedSecret(key)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("KEYSTORE_ERROR", e.localizedMessage ?: "Keystore işlemi başarısız.", null)
            }
        }
    }

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        val existing = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
        if (existing != null) {
            return existing
        }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private fun saveEncryptedSecret(key: String, plainValue: String) {
        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val iv = cipher.iv
        val encrypted = cipher.doFinal(plainValue.toByteArray(StandardCharsets.UTF_8))
        val combined = ByteArray(iv.size + encrypted.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(encrypted, 0, combined, iv.size, encrypted.size)

        val encoded = Base64.encodeToString(combined, Base64.NO_WRAP)
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(key, encoded).apply()
    }

    private fun readEncryptedSecret(key: String): String? {
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val encoded = prefs.getString(key, null) ?: return null
        val combined = Base64.decode(encoded, Base64.NO_WRAP)
        if (combined.size <= GCM_IV_LENGTH) return null

        val iv = combined.copyOfRange(0, GCM_IV_LENGTH)
        val encrypted = combined.copyOfRange(GCM_IV_LENGTH, combined.size)
        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateSecretKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        val plain = cipher.doFinal(encrypted)
        return String(plain, StandardCharsets.UTF_8)
    }

    private fun deleteEncryptedSecret(key: String) {
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().remove(key).apply()
    }
}
