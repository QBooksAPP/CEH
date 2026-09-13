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
    private var bankPicker: BankStatementPicker? = null
    companion object {
        private const val ENVIRONMENT_METADATA = "com.concreteequipmenthire.ceh.ENVIRONMENT"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bankPicker = BankStatementPicker(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.concreteequipmenthire.ceh/bank_picker")
            .setMethodCallHandler { call, result ->
                if (call.method != "pick") result.notImplemented()
                else if (!isBankingPackage()) result.error("UNAVAILABLE", "Unavailable", null)
                else bankPicker!!.pick(result)
            }
        // Read-only document viewing. Never use ACTION_SEND or grant write access.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.concreteequipmenthire.ceh/bank_document")
            .setMethodCallHandler { call, result ->
                try {
                    check(isBankingPackage()) { "Bank documents are unavailable for this package." }
                    if (call.method != "viewOriginal") { result.notImplemented(); return@setMethodCallHandler }
                    val root = File(cacheDir, "bank-originals").canonicalFile
                    val file = File(call.argument<String>("path") ?: error("Missing file")).canonicalFile
                    check(file.isFile && file.parentFile == root && file.extension in listOf("xlsx", "csv"))
                    val uri = FileProvider.getUriForFile(this, "$packageName.bank_documents", file)
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, if (file.extension == "xlsx") "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" else "text/csv")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(intent)
                    result.success(null)
                } catch (error: Throwable) { result.error("DOCUMENT_VIEW_FAILED", "No compatible viewer or document unavailable.", null) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UpdateTrust.CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    requireUpdateRuntime()
                    val path = call.argument<String>("path")
                        ?: error("An APK path is required.")
                    when (call.method) {
                        "inspectApk" -> result.success(inspectApk(path).asMap())
                        "launchInstaller" -> result.success(launchInstaller(path))
                        else -> result.notImplemented()
                    }
                } catch (error: Throwable) {
                    result.error(
                        "CEH_UPDATE_REJECTED",
                        error.message ?: "The update was rejected.",
                        null,
                    )
                }
            }
    }

    private fun isBankingPackage(): Boolean =
        packageName == UpdateTrust.PACKAGE

    private fun requireUpdateRuntime() {
        check(applicationContext.packageName == UpdateTrust.PACKAGE) {
            "The update bridge is unavailable for this package."
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (bankPicker?.complete(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun approvedApkFile(path: String): File {
        val updateRoot = File(cacheDir, UpdateTrust.CACHE).canonicalFile
        val apk = File(path).canonicalFile
        check(apk.isFile && apk.name.endsWith(".apk", ignoreCase = false)) {
            "The downloaded APK is unavailable."
        }
        check(apk.path.startsWith(updateRoot.path + File.separator)) {
            "The APK is outside the private update cache."
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
        } ?: error("Android could not parse the downloaded APK.")
    }

    @Suppress("DEPRECATION")
    private fun signingCertificateSha256(info: PackageInfo): String {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            info.signatures
        } ?: error("The APK has no signing certificate.")
        check(signatures.size == 1) {
            "The APK must have exactly one current signer."
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
            inspected.applicationId == packageName &&
                inspected.environment == UpdateTrust.ENVIRONMENT &&
                inspected.versionCode > installedVersion &&
                inspected.versionCode >= UpdateTrust.MINIMUM_VERSION &&
                inspected.signingCertificateSha256 == UpdateTrust.CERTIFICATE_SHA256,
        ) { "The package failed the final CEH installation check." }

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
            UpdateTrust.PROVIDER,
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
