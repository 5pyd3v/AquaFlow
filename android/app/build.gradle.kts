import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    FileInputStream(localPropertiesFile).use { localProperties.load(it) }
}

// Google Maps requires a manifest placeholder. We source it from an
// environment variable first (CI-friendly), falling back to a key in
// local.properties (`MAPS_API_KEY=...`) for local development so no
// secret ever needs to be hardcoded in version-controlled Gradle files.
val mapsApiKey: String =
    System.getenv("GOOGLE_MAPS_API_KEY_ANDROID")
        ?: (localProperties.getProperty("MAPS_API_KEY") ?: "")

android {
    namespace = "com.aquaflow.app"
    // SDK 36 (Android 16) / NDK 28 — matched to the installed toolchain
    // rather than left at Flutter's older defaults. AGP 8.9+ and
    // Gradle 8.12+ (see settings.gradle.kts / gradle-wrapper.properties)
    // are required to recognize compileSdk 36; older AGP versions fail
    // with "Unsupported compileSdk" at sync time.
    compileSdk = 36
    // Match this to whatever NDK version is actually installed in your
    // Android SDK Manager (Android Studio → Settings → SDK Manager →
    // SDK Tools → NDK). Gradle fails the build with "NDK not found" if
    // this string doesn't exactly match an installed version — it is
    // not a minimum-version range, it's a literal folder name under
    // `<sdk>/ndk/`.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.aquaflow.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    signingConfigs {
        create("release") {
            // Wire real keystore values here (or via local.properties)
            // before shipping to Play Console — debug signing is used
            // for `flutter run` so the project works out of the box.
            storeFile = if (localPropertiesFile.exists() && localProperties.getProperty("RELEASE_STORE_FILE") != null)
                file(localProperties.getProperty("RELEASE_STORE_FILE")) else null
            storePassword = localProperties.getProperty("RELEASE_STORE_PASSWORD")
            keyAlias = localProperties.getProperty("RELEASE_KEY_ALIAS")
            keyPassword = localProperties.getProperty("RELEASE_KEY_PASSWORD")
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = if (localProperties.getProperty("RELEASE_STORE_FILE") != null)
                signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        getByName("debug") {
            applicationIdSuffix = ".debug"
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
}
