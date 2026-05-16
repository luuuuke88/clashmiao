plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.clashmiao.clashmiao"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.clashmiao.clashmiao"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        ndk {
            abiFilters += listOf("x86_64", "armeabi-v7a", "arm64-v8a")
        }
    }

    buildFeatures {
        aidl = true
    }

    testOptions {
        unitTests {
            // host JVM 跑 Android stub 时遇到没实现的 framework call 直接返回默认值
            // 而不是 throw —— 单测里如果意外触到 SDK 方法不会爆栈。
            isReturnDefaultValues = true
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar", "*.jar"))))
    implementation("com.google.code.gson:gson:2.10.1")
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.lifecycle:lifecycle-livedata-ktx:2.6.2")

    // Kotlin unit tests for engine/ + core/ —— 跑在 host JVM 上，不需要 emulator。
    // Robolectric 暂不引入：第一次跑要下 SDK 34 instrumented jar（>100MB）经常
    // 卡 timeout，性价比低。当前覆盖的 Prefs / PermissionGate / LogBuffer 都
    // 已经设计成可纯 JUnit 测的形态（关键逻辑抽到不依赖 Android Context 的函数）。
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
