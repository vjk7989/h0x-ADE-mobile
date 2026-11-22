plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "tech.pavii.hyperox"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "tech.pavii.hyperox"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One fixed, public debug key for every build (CI and local), so each
    // debug APK installs over the previous one. It is not a secret and is
    // never used for a published release (see the release signingConfig).
    signingConfigs {
        getByName("debug") {
            storeFile = file("../debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        // Release key comes from the environment (CI tag builds). There is no
        // fallback to the debug key: a release build without it fails.
        val releaseKeystore = System.getenv("ANDROID_KEYSTORE_PATH")
        if (!releaseKeystore.isNullOrEmpty()) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    // Debug builds carry the public debug key, so they get their own
    // applicationId and can never be installed over the real app. Only the
    // debug type: the Flutter plugin copies other types to library projects,
    // which cannot set a suffix.
    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
        }
        getByName("profile") {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    val releaseTask = allTasks.any { it.project == project && it.name.endsWith("Release") }
    if (releaseTask && android.signingConfigs.findByName("release") == null) {
        throw GradleException("Release build needs ANDROID_KEYSTORE_PATH and the signing env vars; the debug key is never used for release.")
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
