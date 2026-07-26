package com.example.nusa_kasir

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.net.Uri
import android.provider.ContactsContract
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nusa_kasir/contacts"
    private val BT_CHANNEL = "com.nusa_kasir/bluetooth"

    // Queue-based dispatch — survives activity recreation
    // because configureFlutterEngine re-creates the channel on each recreate.
    private var contactCallId = 0
    private val contactResults = mutableMapOf<Int, MethodChannel.Result>()

    private var btPendingResult: MethodChannel.Result? = null

    @Deprecated("Deprecated in Java — required for both contact picker and BT enable")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            1001 -> { // Contact picker
                val entry = contactResults.entries.firstOrNull() ?: return
                contactResults.remove(entry.key)
                val res = entry.value

                try {
                    if (resultCode != RESULT_OK || data == null) {
                        res.success(null) // User cancelled
                        return
                    }
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
                } catch (e: Exception) {
                    res.error("READ_FAILED", e.message, null)
                }
            }
            2001 -> { // Bluetooth enable
                btPendingResult?.success(resultCode == RESULT_OK)
                btPendingResult = null
            }
        }
    }

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
                        btPendingResult = result
                        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                        startActivityForResult(intent, 2001)
                    } else {
                        result.success(true)
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
                    val id = ++contactCallId
                    contactResults[id] = result
                    val intent = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI).apply {
                        type = ContactsContract.CommonDataKinds.Phone.CONTENT_TYPE
                    }
                    startActivityForResult(intent, 1001)
                } catch (e: Exception) {
                    result.error("PICK_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
