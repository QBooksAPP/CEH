package com.concreteequipmenthire.ceh

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/** User-selected content only; bounded read, no storage permission or persistent URI grant. */
class BankStatementPicker(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    fun pick(result: MethodChannel.Result) {
        if (pending != null) { result.error("PICKER_OPEN", "Picker already open", null); return }
        pending = result
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/csv", "text/comma-separated-values", "application/vnd.ms-excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
            }, 6812)
        } catch (e: Exception) { pending = null; result.error("PICKER_FAILED", "Unable to open file picker", null) }
    }
    fun complete(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != 6812) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return true }
        Thread {
            try {
                val resolver = activity.contentResolver
                var name = ""
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) name = it.getString(0)
                }
                require(name.lowercase().endsWith(".csv") || name.lowercase().endsWith(".xlsx"))
                val output = ByteArrayOutputStream()
                resolver.openInputStream(uri)!!.use { input ->
                    val buffer = ByteArray(16384)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        require(output.size() + n <= 10000000)
                        output.write(buffer, 0, n)
                    }
                }
                require(output.size() > 0)
                activity.runOnUiThread { result.success(mapOf("name" to name, "bytes" to output.toByteArray())) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("STATEMENT_READ_FAILED", "Choose a readable CSV/XLSX file up to 10 MB", null) }
            }
        }.start()
        return true
    }
}
