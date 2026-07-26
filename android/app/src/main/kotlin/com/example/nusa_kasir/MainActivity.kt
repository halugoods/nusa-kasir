package com.example.nusa_kasir

import android.content.Intent
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nusa_kasir/contacts"
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "pickContact") {
                try {
                    pendingResult = result
                    val intent = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI).apply {
                        type = ContactsContract.CommonDataKinds.Phone.CONTENT_TYPE
                    }
                    startActivityForResult(intent, 1001)
                } catch (e: Exception) {
                    pendingResult = null
                    result.error("PICK_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        val res = pendingResult ?: return
        pendingResult = null

        if (requestCode != 1001) return

        try {
            if (resultCode == RESULT_OK && data != null) {
                val uri: android.net.Uri? = data.data
                if (uri == null) {
                    res.success(null)
                    return
                }
                val projection = arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                )
                val cursor = contentResolver.query(uri, projection, null, null, null)
                if (cursor != null) {
                    cursor.use {
                        if (it.moveToFirst()) {
                            val name = it.getString(0) ?: ""
                            val phone = it.getString(1) ?: ""
                            res.success(mapOf("name" to name, "phone" to phone))
                        } else {
                            res.success(null)
                        }
                    }
                } else {
                    res.success(null)
                }
            } else {
                res.success(null) // User cancelled
            }
        } catch (e: Exception) {
            res.error("READ_FAILED", e.message, null)
        }
    }
}
