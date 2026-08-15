plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.stickerstudio.app"
    // Pinned to 37 rather than flutter.compileSdkVersion (36): receive_sharing_intent
    // 1.9.0 declares an AAR metadata minimum of 37 and the build fails outright
    // below it. compileSdk only controls which APIs we may reference — it does not
    // raise minSdk or targetSdk, so the API 36 test device is unaffected.
    // AGP 9.0.1 prints a "maximum recommended compile SDK is 36" warning; harmless.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.stickerstudio.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
    // Semantic search (Task 10 Step 4). MediaPipe's TextEmbedder rather than raw
    // tflite_flutter: the Universal Sentence Encoder needs SentencePiece
    // tokenisation to turn text into token ids, and tflite_flutter only exposes
    // raw tensors — we would have to reimplement that tokeniser in Dart. This
    // does it natively, and the Kotlin/MethodChannel pattern already exists here
    // for the WebP encoder and the sticker export.
    implementation("com.google.mediapipe:tasks-text:0.10.14")
}

// The 5.8 MB universal_sentence_encoder.tflite in src/main/assets must NOT be
// compressed: MediaPipe memory-maps the model straight out of the APK, which
// only works on a stored (uncompressed) entry.
androidComponents {
    onVariants { variant ->
        variant.packaging.resources.excludes.add("META-INF/DEPENDENCIES")
    }
}

android {
    androidResources {
        noCompress += "tflite"
    }
}
