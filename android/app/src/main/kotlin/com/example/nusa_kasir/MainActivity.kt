package com.example.nusa_kasir

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.provider.ContactsContract
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nusa_kasir/contacts"
    private val BT_CHANNEL = "com.nusa_kasir/bluetooth"
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Bluetooth channel ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isBluetoothEnabled" -> {
                    val adapter = BluetoothAdapter.getDefaultAdapter()
                    result.success(adapter?.isEnabled ?: false)
                }
                "requestBluetoothEnable" -> {
                    val adapter = BluetoothAdapter.getDefaultAdapter()
                    if (adapter == null) {
                        result.success(false)
                    } else if (!adapter.isEnabled) {
                        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                        startActivityForResult(intent, 2001)
                        result.success(true)
                    } else {
                        result.success(true) // already on
                    }
                }
                "openBluetoothSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "openAppSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        intent.data = android.net.Uri.parse("package:$packageName")
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ── Contact picker channel ──
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
