import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
} else {
    logger.lifecycle(
        "No android/key.properties found; release APKs will use the debug signing config.",
    )
}

android {
    namespace = "com.clashmiao.clashmiao"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

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
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        ndk {
            abiFilters += listOf("x86_64", "armeabi-v7a", "arm64-v8a")
        }
    }

    splits {
        abi {
            isEnable = true
            reset()
            include("x86_64", "armeabi-v7a", "arm64-v8a")
            isUniversalApk = true
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

    if (hasKeystore) {
        signingConfigs {
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
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            ndk {
                abiFilters += listOf("x86_64", "armeabi-v7a", "arm64-v8a")
                debugSymbolLevel = "FULL"
            }
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
