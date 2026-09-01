import java.util.Base64

val requestedCehTasks = gradle.startParameter.taskNames.map { it.lowercase() }
val buildsStagingRelease = requestedCehTasks.any {
    it.contains("staging") && it.contains("release")
}
val buildsProductionRelease = requestedCehTasks.any {
    it.contains("production") && it.contains("release")
}
val stagingKeystorePath = System.getenv("CEH_STAGING_KEYSTORE_PATH")
val stagingStorePassword = System.getenv("CEH_STAGING_KEYSTORE_PASSWORD")
val stagingKeyAlias = System.getenv("CEH_STAGING_KEY_ALIAS")
val stagingSigningAvailable = !stagingKeystorePath.isNullOrBlank() &&
    !stagingStorePassword.isNullOrBlank() &&
    stagingKeyAlias == "ceh-staging"

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.concreteequipmenthire.ceh"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.concreteequipmenthire.ceh"
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

    flavorDimensions += "environment"
    productFlavors {
        create("production") {
            dimension = "environment"
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
        }
    }

    signingConfigs {
        if (stagingSigningAvailable) {
            create("stagingPermanent") {
                storeFile = file(stagingKeystorePath!!)
                storePassword = stagingStorePassword
                keyAlias = stagingKeyAlias
                keyPassword = stagingStorePassword
            }
        }
    }

    buildTypes {
        release {
            if (buildsStagingRelease) {
                require(!buildsProductionRelease) {
                    "Production and staging release variants must be built separately."
                }
                require(stagingSigningAvailable) {
                    "The permanent CEH STAGING signing credential is required."
                }
                signingConfig = signingConfigs.getByName("stagingPermanent")
            } else {
                // Production retains its existing local/CI signing resolution.
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    implementation("androidx.core:core:1.15.0")
}

gradle.taskGraph.whenReady {
    val taskNames = allTasks.map { it.name.lowercase() }
    val buildsStaging = taskNames.any { it.contains("staging") }
    val buildsProduction = taskNames.any { it.contains("production") }
    val dartDefines = (project.findProperty("dart-defines") as String?)
        ?.split(',')
        ?.filter { it.isNotBlank() }
        ?.associate { encoded ->
            val decoded = String(Base64.getDecoder().decode(encoded))
            val separator = decoded.indexOf('=')
            require(separator > 0) { "Invalid dart-define supplied to CEH build." }
            decoded.substring(0, separator) to decoded.substring(separator + 1)
        }
        ?: emptyMap()

    if (buildsStaging) {
        require(dartDefines["CEH_ENVIRONMENT"] == "staging") {
            "Staging flavor requires CEH_ENVIRONMENT=staging."
        }
        require(
            dartDefines["CEH_API_BASE_URL"] ==
                "https://staging.concretehireng.com",
        ) { "Staging flavor requires the approved staging API origin." }
        require(dartDefines["CEH_UPDATE_CHECKS"] == "false") {
            "Staging flavor must disable production update checks."
        }
    }

    if (buildsProduction) {
        require(dartDefines["CEH_ENVIRONMENT"] in listOf(null, "production")) {
            "Production flavor cannot use a staging environment define."
        }
        require(
            dartDefines["CEH_API_BASE_URL"] in
                listOf(null, "https://qbook.concretehireng.com"),
        ) { "Production flavor cannot use the staging API origin." }
        require(dartDefines["CEH_UPDATE_CHECKS"] in listOf(null, "true")) {
            "Production flavor must retain production update checks."
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
