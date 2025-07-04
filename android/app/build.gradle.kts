plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Add the Google services Gradle plugin
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.flutter_projects"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.flutter_projects"
        minSdk = 23  // 這個版本已經足夠支援 Google Sign-In
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

dependencies {
    // Import the Firebase BoM (使用最新版本)
    implementation(platform("com.google.firebase:firebase-bom:33.16.0"))

    // 移除這個重複的依賴，因為它不是運行時依賴
    // implementation("com.google.gms:google-services:4.4.3")

    // Firebase Analytics (保持現有的)
    implementation("com.google.firebase:firebase-analytics")

    // 新增：Firebase Auth - 用於 Google Sign-In
    implementation("com.google.firebase:firebase-auth")

    // 新增：Google Sign-In SDK (使用最新版本)
    implementation("com.google.android.gms:play-services-auth:21.2.0")

    // 新增：Firebase Firestore (如果還沒有的話)
    implementation("com.google.firebase:firebase-firestore")
}

flutter {
    source = "../.."
}