import java.io.FileInputStream
import java.util.Properties

// بيانات توقيع الإصدار النهائي (android/key.properties، وهو مش بيترفع على GitHub).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.wassally.app"
   compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // اسم الحزمة بتاع التطبيق. لو غيّرته لازم تسجّل تطبيق أندرويد جديد في Firebase.
        applicationId = "com.wassally.app"
        minSdk = flutter.minSdkVersion
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // لا نُجبر Debug على امتلاك مفتاح Release.
            // عند وجود المفتاح فقط، نربط Release به؛ وعند غيابه نمنع مهام إخراج Release أدناه.
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
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

// فحص مفتاح التوقيع عند تنفيذ مهام إخراج Release فقط، وليس أثناء تقييم إعدادات Gradle.
tasks.configureEach {
    val isReleaseArtifactTask =
        name.endsWith("Release") &&
            (name.startsWith("assemble") ||
                name.startsWith("bundle") ||
                name.startsWith("package"))

    if (isReleaseArtifactTask) {
        doFirst {
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(
                    "Missing android/key.properties: release APK/AAB builds require the existing private upload key."
                )
            }
        }
    }
}
