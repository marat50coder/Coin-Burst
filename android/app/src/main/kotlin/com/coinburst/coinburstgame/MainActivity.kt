package com.coinburst.coinburstgame

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts two concerns:
 *
 *  1. `FLAG_KEEP_SCREEN_ON` — so a long spin inside the slot game does
 *     not get interrupted by the display timing out.
 *  2. The `kqz/picker` MethodChannel — PortalScene's WebView calls into
 *     this to open the Android system document picker. Returning the
 *     content URIs lets `webview_flutter_android` finish the `<input
 *     type="file">` request.
 *
 * The channel name is per-project (differs from the sibling template's
 * `relay/upload`) so the system-level MethodChannel inventory stays
 * unique across our Play portfolio.
 */
class MainActivity : FlutterActivity() {

    private var pendingResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep screen on during gameplay
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PICKER_CHANNEL
        ).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "pick" -> {
                    val multiple = call.argument<Boolean>("multiple") ?: false
                    val mimeTypes = (call.argument<List<String>>("mimeTypes")
                        ?: emptyList())
                        .filter { it.isNotBlank() }
                    pendingResult = result
                    launchPicker(multiple, mimeTypes)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun launchPicker(multiple: Boolean, mimeTypes: List<String>) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
            if (mimeTypes.isNotEmpty()) {
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
            } else {
                type = "*/*"
            }
        }
        try {
            startActivityForResult(
                Intent.createChooser(intent, "Choose file"),
                PICK_REQUEST
            )
        } catch (t: Throwable) {
            pendingResult?.success(emptyList<String>())
            pendingResult = null
        }
    }

    @Deprecated("Preserved for Flutter WebView compat.")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_REQUEST) return
        val resolver = pendingResult
        pendingResult = null
        if (resolver == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            resolver.success(emptyList<String>())
            return
        }
        val picked = mutableListOf<String>()
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) {
                clip.getItemAt(i).uri?.let { picked += it.toString() }
            }
        }
        if (picked.isEmpty()) {
            data.data?.let { picked += it.toString() }
        }
        // Grant long-term read permission on each uri so the WebView
        // can stream the file after this Activity has moved on.
        picked.forEach { uri ->
            try {
                contentResolver.takePersistableUriPermission(
                    Uri.parse(uri),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) { /* some providers refuse */ }
        }
        resolver.success(picked)
    }

    private companion object {
        const val PICKER_CHANNEL = "kqz/picker"
        const val PICK_REQUEST = 0x9A14
    }
}
