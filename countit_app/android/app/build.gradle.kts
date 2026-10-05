import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // On the classpath only; applied below when a flavor has its google-services.json.
    id("com.google.gms.google-services") apply false
}

// FCM (docs/PUSH.md): google-services.json lives per flavor in
// src/<flavor>/ and is not committed. The plugin is applied only when some
// flavor has it, so CI and flavors without Firebase still build (the app then
// falls back to NoopPushMessaging); a flavor without the file is skipped.
val firebaseFlavors =
    listOf("local", "staging", "prod").filter { file("src/$it/google-services.json").exists() }
if (firebaseFlavors.isNotEmpty()) {
    apply(plugin = "com.google.gms.google-services")
    extensions.configure<com.google.gms.googleservices.GoogleServicesPlugin.GoogleServicesPluginConfig> {
        missingGoogleServicesStrategy =
            com.google.gms.googleservices.GoogleServicesPlugin.MissingGoogleServicesStrategy.IGNORE
    }
}

// Release signing (COU-135): android/key.properties (never committed; see
// README.md, «Release») or, in CI, written from the ANDROID_KEYSTORE_* secrets.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties =
    Properties().apply {
        if (keystorePropertiesFile.exists()) keystorePropertiesFile.inputStream().use { load(it) }
    }
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    val required = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    val missing = required.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    if (missing.isNotEmpty()) {
        throw GradleException("android/key.properties is missing: ${missing.joinToString()} (see README.md, Release)")
    }
    val store = file(keystoreProperties.getProperty("storeFile"))
    if (!store.exists()) {
        throw GradleException("Keystore not found at $store (storeFile in android/key.properties)")
    }
}

android {
    namespace = "ec.countit.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ec.countit.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // versionName/versionCode come from `version: x.y.z+N` in pubspec.yaml.
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One installable app per environment (COU-11); run with
    // flutter run --flavor <local|staging|prod> --dart-define-from-file=env/<same>.json
    // AGP disables resValue by default; the flavors use it for the app name.
    buildFeatures {
        resValues = true
    }

    flavorDimensions += "env"
    productFlavors {
        create("local") {
            dimension = "env"
            applicationIdSuffix = ".local"
            versionNameSuffix = "-local"
            resValue("string", "app_name", "Count It! Local")
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "Count It! Staging")
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Count It!")
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
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
            // Without key.properties the release build still works locally but is
            // signed with the debug key: Play rejects it, it is only for testing.
            signingConfig =
                if (hasReleaseSigning) {
                    signingConfigs.getByName("release")
                } else {
                    logger.warn("WARNING: android/key.properties not found; release signed with the DEBUG key (not publishable).")
                    signingConfigs.getByName("debug")
                }
            // R8: shrink, optimize and obfuscate the Java/Kotlin side (the Dart side is
            // obfuscated by --obfuscate, scripts/build_release.sh).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
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
