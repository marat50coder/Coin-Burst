import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Google Services (Firebase). Resolves com.google.firebase:firebase-*
    // artifacts from android/app/google-services.json at build time. The
    // JSON file ships inside the repo so the gray branch can light up on
    // first launch — if you ever rotate the Firebase project, drop a
    // fresh json file in the same place.
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and
    // Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.coinburst.coinburstgame"
    // Pinned per gray_part_pitfalls §19 floor + §2 CheckAarMetadata rule.
    compileSdk = 36
    // Pinned per §11 — 16 KB page-size compliance (Android 15+).
    ndkVersion = "28.2.13676358"

    compileOptions {
        // §5 — flutter_local_notifications ≥ 18.x needs java.time.* on
        // minSdk 24 → core library desugaring is mandatory.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.coinburst.coinburstgame"
        // §TL;DR — Firebase + AppsFlyer floor is Android 8.0 (API 26).
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Release artifacts are signed with the upload keystore when
            // android/key.properties is present. That file and the .jks
            // stay out of git.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Keep minify off — Firebase/AppsFlyer historically need
            // specific Keep rules that drift between SDK releases.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // The pre-built Rust gateway lives under
    // android/app/src/main/jniLibs/<abi>/libcoinburst_gateway.so and is
    // picked up automatically by this default source set.
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Required so `Theme.SplashScreen` + `windowSplashScreenBackground`
    // + `windowSplashScreenAnimatedIcon` resolve on both pre- and
    // post-Android-12 devices (compat shim).
    implementation("androidx.core:core-splashscreen:1.0.1")
}

flutter {
    source = "../.."
}
