plugins {
    id("com.android.application")
    // плагин flutter подключаем после android
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigning = listOf(
    "ANDROID_KEYSTORE_PATH",
    "ANDROID_KEYSTORE_PASSWORD",
    "ANDROID_KEY_ALIAS",
    "ANDROID_KEY_PASSWORD",
).associateWith { providers.environmentVariable(it).orNull?.takeIf { value -> value.isNotBlank() } }

// проверяем только когда просят релизную задачу, отладочной сборке релизные секреты не нужны
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release") }) {
        val missing = releaseSigning.filterValues { it == null }.keys
        check(missing.isEmpty()) { "Missing Android release signing environment variables: ${missing.joinToString()}" }
        check(file(releaseSigning.getValue("ANDROID_KEYSTORE_PATH")!!).isFile) {
            "ANDROID_KEYSTORE_PATH must point to an existing release keystore"
        }
    }
}

extensions.configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "com.magisky.reschoolbeta"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // свой уникальный идентификатор приложения
        applicationId = "com.magisky.reschoolbeta"
        // значения ниже подгоняются под нужды приложения
        // подробности есть в документации flutter про настройку gradle
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseSigning["ANDROID_KEYSTORE_PATH"]?.let { file(it) }
            storePassword = releaseSigning["ANDROID_KEYSTORE_PASSWORD"]
            keyAlias = releaseSigning["ANDROID_KEY_ALIAS"]
            keyPassword = releaseSigning["ANDROID_KEY_PASSWORD"]
        }
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all {
            it.systemProperty("widget.previewDir", layout.buildDirectory.dir("widget-previews").get().asFile.absolutePath)
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

// проверяем поведение виджетов с обеими реализациями коллекций
dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
}

// agp 9 включает ресурсы flutter и в тестовый apk robolectric
tasks.matching { it.name == "packageDebugUnitTestForUnitTest" }.configureEach {
    dependsOn("copyFlutterAssetsDebug")
}
