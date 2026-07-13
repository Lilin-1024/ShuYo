package cn.edu.shu.lehu_client

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cn.edu.shu.lehu_client/image_picker"
        ).setMethodCallHandler { call, result ->
            if (call.method == "pickImage") {
                pickImage(result)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun pickImage(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "Image picker is already open", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
        }
        startActivityForResult(intent, REQUEST_PICK_IMAGE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_IMAGE) {
            return
        }
        val result = pendingResult ?: return
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }
        val uri = data.data!!
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            if (bytes == null || bytes.isEmpty()) {
                result.success(null)
                return
            }
            result.success(
                mapOf(
                    "bytes" to bytes,
                    "filename" to displayName(uri),
                    "mimeType" to (contentResolver.getType(uri) ?: "image/jpeg")
                )
            )
        } catch (error: Exception) {
            result.error("read_failed", error.message, null)
        }
    }

    private fun displayName(uri: Uri): String {
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(uri, null, null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    return cursor.getString(index)
                }
            }
        } finally {
            cursor?.close()
        }
        return "image.jpg"
    }

    companion object {
        private const val REQUEST_PICK_IMAGE = 9101
    }
}
