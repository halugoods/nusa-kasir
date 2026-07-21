package com.example.nusa_kasir

import android.content.Intent
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nusa_kasir/contacts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "pickContact") {
                try {
                    val intent = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI).apply {
                        type = ContactsContract.CommonDataKinds.Phone.CONTENT_TYPE
                    }
                    startActivityForResult(intent, PICK_CONTACT_REQUEST)
                    pendingResult = result
                } catch (e: Exception) {
                    result.error("PICK_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private var pendingResult: MethodChannel.Result? = null
    private val PICK_CONTACT_REQUEST = 1001

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_CONTACT_REQUEST) {
            val res = pendingResult ?: return
            pendingResult = null
            if (resultCode == RESULT_OK && data != null) {
                try {
                    val uri = data.data ?: run { res.error("NO_DATA", "No contact selected", null); return }
                    val cursor = contentResolver.query(uri, null, null, null, null)
                    if (cursor != null) {
                        cursor.use {
                            if (it.moveToFirst()) {
                                val nameIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                                val phoneIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                                val name = if (nameIdx >= 0) it.getString(nameIdx) ?: "" else ""
                                val phone = if (phoneIdx >= 0) it.getString(phoneIdx) ?: "" else ""
                                res.success(mapOf("name" to name, "phone" to phone))
                            } else {
                                res.error("READ_FAILED", "Cannot read contact", null)
                            }
                        }
                    } else {
                        res.error("READ_FAILED", "Cannot read contact", null)
                    }
                } catch (e: Exception) {
                    res.error("READ_FAILED", e.message, null)
                }
            } else {
                res.success(null) // User cancelled
            }
        }
    }
}
