plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFields = listOf("KANEO_ANDROID_KEYSTORE", "KANEO_ANDROID_STORE_PASSWORD",
    "KANEO_ANDROID_KEY_ALIAS", "KANEO_ANDROID_KEY_PASSWORD")
val releaseSigning = signingFields.associateWith { System.getenv(it).orEmpty() }
val hasReleaseSigning = releaseSigning.values.any { it.isNotEmpty() }
if (hasReleaseSigning && releaseSigning.values.any { it.isEmpty() }) {
    throw GradleException("Incomplete release signing configuration; use .github/scripts/mobile_release.py")
}

android {
    namespace = "app.kaneo.kaneo_app"
    // flutter_local_notifications needs 37.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.kaneo.kaneo_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseSigning.getValue("KANEO_ANDROID_KEYSTORE"))
                storePassword = releaseSigning.getValue("KANEO_ANDROID_STORE_PASSWORD")
                keyAlias = releaseSigning.getValue("KANEO_ANDROID_KEY_ALIAS")
                keyPassword = releaseSigning.getValue("KANEO_ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // CI can compile an unsigned package. Distribution requires the administrator's key;
            // a missing key must never silently produce a package signed with the debug identity.
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("release") else null
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
