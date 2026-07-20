package work.shuyo.app

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
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
            "work.shuyo.app/image_picker"
        ).setMethodCallHandler { call, result ->
            if (call.method == "pickImage") {
                pickImage(result)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "work.shuyo.app/image_saver"
        ).setMethodCallHandler { call, result ->
            if (call.method == "saveImage") {
                saveImage(
                    call.argument("bytes"),
                    call.argument("filename"),
                    call.argument("mimeType"),
                    result
                )
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "work.shuyo.app/emoji_recents"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getEmojiRecents" -> result.success(loadEmojiRecents())
                "setEmojiRecents" -> {
                    saveEmojiRecents(call.argument("shortcodes"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun pickImage(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "Image picker is already open", null)
            return
        }
        pendingResult = result
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
            }
        } else {
            Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
                type = "image/*"
            }
        }
        try {
            startActivityForResult(intent, REQUEST_PICK_IMAGE)
        } catch (error: Exception) {
            pendingResult = null
            result.error("picker_unavailable", error.message, null)
        }
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

    private fun saveImage(
        bytes: ByteArray?,
        filename: String?,
        mimeType: String?,
        result: MethodChannel.Result
    ) {
        if (bytes == null || bytes.isEmpty()) {
            result.error("empty_image", "Image bytes are empty", null)
            return
        }
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, filename ?: "lehu_image.jpg")
            put(MediaStore.Images.Media.MIME_TYPE, mimeType ?: "image/jpeg")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    "${Environment.DIRECTORY_PICTURES}/Lehu"
                )
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }
        val resolver = contentResolver
        var uri: Uri? = null
        try {
            uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            if (uri == null) {
                result.error("save_failed", "Cannot create image entry", null)
                return
            }
            resolver.openOutputStream(uri)?.use { output ->
                output.write(bytes)
            } ?: throw IllegalStateException("Cannot open image output stream")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            }
            result.success(uri.toString())
        } catch (error: Exception) {
            if (uri != null) {
                resolver.delete(uri, null, null)
            }
            result.error("save_failed", error.message, null)
        }
    }

    private fun loadEmojiRecents(): List<String> {
        val raw = getPreferences(MODE_PRIVATE).getString(KEY_EMOJI_RECENTS, "") ?: ""
        if (raw.isBlank()) {
            return emptyList()
        }
        return raw.split("\n").filter { it.isNotBlank() }
    }

    private fun saveEmojiRecents(shortcodes: List<String>?) {
        val value = shortcodes.orEmpty()
            .filter { it.isNotBlank() }
            .joinToString("\n")
        getPreferences(MODE_PRIVATE)
            .edit()
            .putString(KEY_EMOJI_RECENTS, value)
            .apply()
    }

    companion object {
        private const val REQUEST_PICK_IMAGE = 9101
        private const val KEY_EMOJI_RECENTS = "emoji_recents"
    }
}
