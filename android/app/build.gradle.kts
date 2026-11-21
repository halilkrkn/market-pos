import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Faz 7C — Üretim imzalama: android/key.properties (Git'e EKLENMEZ) üzerinden okunur.
// storeFile, storePassword, keyAlias, keyPassword alanlarını içermelidir.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists()

// Yalnızca geliştirme/saha denemesi için bilinçli gevşetmeler (varsayılan: kapalı).
// MMS_ALLOW_DEBUG_SIGNING=true  -> key.properties yoksa release'i debug anahtarıyla imzala
// MMS_ALLOW_CLEARTEXT=true      -> release derlemede şifresiz HTTP'ye izin ver (TLS'siz Hub)
val allowDebugSigning = System.getenv("MMS_ALLOW_DEBUG_SIGNING") == "true"
val allowReleaseCleartext = System.getenv("MMS_ALLOW_CLEARTEXT") == "true"

android {
    namespace = "com.marketmms.market_pos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.marketmms.market_pos"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Debug/profile: yerel geliştirme Hub'ı HTTP olabilir.
        manifestPlaceholders["usesCleartextTraffic"] = "true"
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Üretim: şifresiz HTTP kapalı; Hub ile yalnızca TLS (sertifika sabitleme) kullanılır.
            manifestPlaceholders["usesCleartextTraffic"] = if (allowReleaseCleartext) "true" else "false"
            signingConfig = when {
                hasReleaseKeystore -> signingConfigs.getByName("release")
                allowDebugSigning -> {
                    logger.warn("UYARI: MMS release derlemesi DEBUG anahtarıyla imzalanıyor (MMS_ALLOW_DEBUG_SIGNING=true). Dağıtıma uygun değildir.")
                    signingConfigs.getByName("debug")
                }
                else -> null
            }
        }
    }
}

// key.properties olmadan üretim paketi sessizce debug anahtarıyla imzalanmaz (fail-closed).
gradle.taskGraph.whenReady {
    val releasePackaging = allTasks.any {
        it.project == project &&
            (it.name.startsWith("package") || it.name.startsWith("bundle") || it.name.startsWith("assemble")) &&
            it.name.contains("Release")
    }
    if (releasePackaging && !hasReleaseKeystore && !allowDebugSigning) {
        throw GradleException(
            "Release imzalama yapılandırılmadı: android/key.properties bulunamadı. " +
                "Üretim anahtarını tanımlayın (bkz. docs/release/ANDROID_RELEASE.md) veya yalnızca " +
                "saha denemesi için MMS_ALLOW_DEBUG_SIGNING=true ortam değişkenini açıkça verin.",
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
