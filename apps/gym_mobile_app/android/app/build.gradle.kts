import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Lee android/app/google-services.json y genera los recursos que
    // FirebaseOptions necesita en runtime. Debe ir DESPUÉS del plugin de
    // Android; si no, no encuentra la configuración del módulo.
    id("com.google.gms.google-services")
}

// AND-1: credenciales de firma de RELEASE cargadas desde android/key.properties,
// el MISMO archivo que el CI genera desde secretos (ver
// .github/workflows/android-release.yml, que decodifica ANDROID_KEY_PROPERTIES_BASE64
// y ANDROID_KEYSTORE_BASE64). key.properties y *.jks están gitignored → NUNCA
// viven en el repo. En local (sin ese archivo) el release cae a 'debug'.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.gympro.mobile"
    compileSdk = 36   // freerasp 7.5 compila contra API 36; AGP 8.9.1+ lo soporta
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.gympro.mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // AND-1: firma de RELEASE desde key.properties (inyectado por el CI desde
        // secretos). NUNCA el keystore de debug ni valores hardcodeados en el repo.
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // Usa la firma de RELEASE sólo si key.properties está presente (CI).
            // En local, sin ese archivo, cae a 'debug' para que `flutter run
            // --release` siga funcionando. El AAB de PRODUCCIÓN se firma SIEMPRE en
            // el pipeline con el keystore real (nunca con el de debug).
            val releaseSigning = signingConfigs.getByName("release")
            signingConfig = if (releaseSigning.storeFile != null) {
                releaseSigning
            } else {
                logger.warn("AND-1: key.properties ausente; firmando RELEASE con DEBUG (solo local, NO publicar).")
                signingConfigs.getByName("debug")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
