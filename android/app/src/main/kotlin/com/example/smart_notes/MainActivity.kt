package com.example.smart_notes

import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "materializePdf") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val uriStr = call.arguments as? String
            if (uriStr.isNullOrBlank()) {
                result.error("BAD_ARGS", "Expected content URI string", null)
                return@setMethodCallHandler
            }

            try {
                val input = openImportStream(uriStr)
                if (input == null) {
                    result.error("OPEN_FAILED", "Could not open URI", null)
                    return@setMethodCallHandler
                }

                val outFile = File(
                    cacheDir,
                    "smart_notes_scan_${System.currentTimeMillis()}.pdf",
                )

                input.use { stream ->
                    FileOutputStream(outFile).use { output ->
                        stream.copyTo(output)
                    }
                }

                result.success(outFile.absolutePath)
            } catch (e: Exception) {
                result.error("COPY_FAILED", e.message, null)
            }
        }
    }

    private fun openImportStream(uriStr: String): InputStream? {
        val trimmed = uriStr.trim()
        if (trimmed.isEmpty()) return null

        val uri = Uri.parse(trimmed)
        contentResolver.openInputStream(uri)?.let { return it }

        val path = when {
            uri.scheme == "file" && !uri.path.isNullOrBlank() -> uri.path
            trimmed.startsWith('/') -> trimmed
            else -> null
        } ?: return null

        val f = File(path)
        return if (f.isFile) FileInputStream(f) else null
    }

    companion object {
        private const val CHANNEL = "com.example.smart_notes/content_uri"
    }
}
