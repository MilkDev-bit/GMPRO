pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // Procesa google-services.json y genera los recursos (values.xml) que
    // FirebaseOptions lee en tiempo de ejecución. Sin este plugin, la app
    // compila pero falla al arrancar con:
    //   "Failed to load FirebaseOptions from resource.
    //    Check that you have defined values.xml correctly."
    // que es exactamente el error que aparecía en tus logs.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
