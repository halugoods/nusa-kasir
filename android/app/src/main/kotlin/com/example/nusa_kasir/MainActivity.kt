package com.example.nusa_kasir

import android.content.Intent
import android.provider.ContactsContract
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nusa_kasir/contacts"
    private var pendingResult: MethodChannel.Result? = null

    // Modern ActivityResultLauncher (replaces deprecated startActivityForResult)
    private val pickContactLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val res = pendingResult ?: return@registerForActivityResult
        pendingResult = null

        try {
            if (result.resultCode == RESULT_OK && result.data != null) {
                val uri = result.data?.data
                if (uri == null) {
                    res.success(null)
                    return@registerForActivityResult
                }
                // Use explicit projection to ensure DISPLAY_NAME and NUMBER are always included
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "pickContact") {
                try {
                    val intent = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI).apply {
                        type = ContactsContract.CommonDataKinds.Phone.CONTENT_TYPE
                    }
                    pendingResult = result
                    pickContactLauncher.launch(intent)
                } catch (e: Exception) {
                    pendingResult = null
                    result.error("PICK_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
