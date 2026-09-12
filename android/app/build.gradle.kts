plugins {
    id("com.android.application")
    id("kotlin-android")

    // Flutter Gradle plugin
    id("dev.flutter.flutter-gradle-plugin")

    // Firebase / Google Services
    id("com.google.gms.google-services")
}

android {
    // Leave this unchanged for now.
    namespace = "com.example.chargepath"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        // IMPORTANT:
        // This must match package_name inside google-services.json.
        applicationId = "com.company.chargepath"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}