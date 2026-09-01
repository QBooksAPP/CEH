package com.concreteequipmenthire.ceh

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.concreteequipmenthire.ceh/staging_update"
        private const val STAGING_PACKAGE = "com.concreteequipmenthire.ceh.staging"
        private const val STAGING_ENVIRONMENT = "STAGING"
        private const val ENVIRONMENT_METADATA = "com.concreteequipmenthire.ceh.ENVIRONMENT"
        private const val STAGING_CERTIFICATE_SHA256 =
            "AFAFCE4A89211E7CBE6F0F665DB977F78CD96EF9343002F0A892B42F3FCDD057"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    requireStagingRuntime()
                    val path = call.argument<String>("path")
                        ?: error("A staging APK path is required.")
                    when (call.method) {
                        "inspectApk" -> result.success(inspectApk(path).asMap())
                        "launchInstaller" -> result.success(launchInstaller(path))
                        else -> result.notImplemented()
                    }
                } catch (error: Throwable) {
                    result.error(
                        "CEH_STAGING_UPDATE_REJECTED",
                        error.message ?: "The staging update was rejected.",
                        null,
                    )
                }
            }
    }

    private fun requireStagingRuntime() {
        check(applicationContext.packageName == STAGING_PACKAGE) {
            "The staging update bridge is unavailable in production."
        }
    }

    private fun approvedApkFile(path: String): File {
        val updateRoot = File(cacheDir, "ceh-staging-updates").canonicalFile
        val apk = File(path).canonicalFile
        check(apk.isFile && apk.name.endsWith(".apk", ignoreCase = false)) {
            "The downloaded staging APK is unavailable."
        }
        check(apk.path.startsWith(updateRoot.path + File.separator)) {
            "The staging APK is outside the private update cache."
        }
        return apk
    }

    @Suppress("DEPRECATION")
    private fun packageArchive(apk: File): PackageInfo {
        val metadataFlag = PackageManager.GET_META_DATA.toLong()
        val signingFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES.toLong()
        } else {
            PackageManager.GET_SIGNATURES.toLong()
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageArchiveInfo(
                apk.path,
                PackageManager.PackageInfoFlags.of(metadataFlag or signingFlag),
            )
        } else {
            packageManager.getPackageArchiveInfo(
                apk.path,
                (metadataFlag or signingFlag).toInt(),
            )
        } ?: error("Android could not parse the downloaded staging APK.")
    }

    @Suppress("DEPRECATION")
    private fun signingCertificateSha256(info: PackageInfo): String {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            info.signatures
        } ?: error("The staging APK has no signing certificate.")
        check(signatures.size == 1) {
            "The staging APK must have exactly one current signer."
        }
        return MessageDigest.getInstance("SHA-256")
            .digest(signatures.single().toByteArray())
            .joinToString(separator = "") { byte -> "%02X".format(byte) }
    }

    private fun inspectApk(path: String): InspectedApk {
        val apk = approvedApkFile(path)
        val info = packageArchive(apk)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        val environment = info.applicationInfo?.metaData
            ?.getString(ENVIRONMENT_METADATA)
            .orEmpty()
        return InspectedApk(
            applicationId = info.packageName,
            versionName = info.versionName.orEmpty(),
            versionCode = versionCode,
            environment = environment,
            signingCertificateSha256 = signingCertificateSha256(info),
        )
    }

    private fun launchInstaller(path: String): String {
        val apk = approvedApkFile(path)
        val inspected = inspectApk(apk.path)
        val installed = packageManager.getPackageInfo(packageName, 0)
        val installedVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            installed.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            installed.versionCode.toLong()
        }
        check(
            inspected.applicationId == STAGING_PACKAGE &&
                inspected.environment == STAGING_ENVIRONMENT &&
                inspected.versionCode > installedVersion &&
                inspected.signingCertificateSha256 == STAGING_CERTIFICATE_SHA256,
        ) { "The package failed the final CEH STAGING installation check." }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return "permissionRequested"
        }

        val contentUri = FileProvider.getUriForFile(
            this,
            "$packageName.update_files",
            apk,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        check(intent.resolveActivity(packageManager) != null) {
            "No Android package installer is available."
        }
        startActivity(intent)
        return "launched"
    }

    private data class InspectedApk(
        val applicationId: String,
        val versionName: String,
        val versionCode: Long,
        val environment: String,
        val signingCertificateSha256: String,
    ) {
        fun asMap(): Map<String, Any> = mapOf(
            "applicationId" to applicationId,
            "versionName" to versionName,
            "versionCode" to versionCode,
            "environment" to environment,
            "signingCertificateSha256" to signingCertificateSha256,
        )
    }
}
