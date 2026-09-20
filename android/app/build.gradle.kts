plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.replylikeme"
    // Flutter's default is 36, but receive_sharing_intent 1.9.0 publishes AAR
    // metadata requiring its consumers to compile against 37, which fails
    // :app:checkReleaseAarMetadata. compileSdk only controls which APIs are
    // available at compile time; targetSdk below stays on Flutter's default, so
    // no runtime behaviour changes.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.replylikeme"
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
        // A fixed key, committed alongside the app, so that every build signs
        // identically and one sideloaded APK can be installed over another.
        // Gradle's auto-generated debug keystore is created fresh on each
        // machine, which means two CI builds get different keys and Android
        // refuses the upgrade with "App not installed".
        //
        // This is NOT a release key and its password is public on purpose.
        // Replace it with a keystore of your own, injected from CI secrets,
        // before publishing anywhere.
        create("sideload") {
            storeFile = file("sideload.keystore")
            storePassword = "sideload"
            keyAlias = "sideload"
            keyPassword = "sideload"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("sideload")
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
