package com.example.nusa_kasir

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.provider.ContactsContract
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nusa_kasir/contacts"
    private val BT_CHANNEL = "com.nusa_kasir/bluetooth"

    // ── Static (companion) pending results — survives activity recreation ──
    companion object {
        private const val TAG = "NUSA"
        private var contactPendingResult: MethodChannel.Result? = null
    }

    private var btPendingResult: MethodChannel.Result? = null

    @Deprecated("Deprecated in Java — required for both contact picker and BT enable")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        Log.d(TAG, "onActivityResult req=$requestCode res=$resultCode hasData=${data != null}")

        when (requestCode) {
            1001 -> { // Contact picker
                val res = contactPendingResult ?: run {
                    Log.w(TAG, "Contact picker result dropped — no pending result (activity recreated?)")
                    return
                }
                contactPendingResult = null

                try {
                    if (resultCode != RESULT_OK || data == null) {
                        Log.d(TAG, "Contact picker: user cancelled")
                        res.success(null)
                        return
                    }
                    val uri = data.data
                    if (uri == null) {
                        Log.w(TAG, "Contact picker: data.data is null")
                        res.success(null)
                        return
                    }
                    Log.d(TAG, "Contact picker: reading URI $uri")
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
                                Log.d(TAG, "Contact picker: found name='$name' phone='$phone'")
                                res.success(mapOf("name" to name, "phone" to phone))
                            } else {
                                Log.w(TAG, "Contact picker: cursor is empty")
                                res.success(null)
                            }
                        }
                    } else {
                        Log.w(TAG, "Contact picker: contentResolver.query returned null cursor")
                        res.success(null)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Contact picker: read failed", e)
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
                    Log.d(TAG, "pickContact: launching contact picker")
                    contactPendingResult = result
                    val intent = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI).apply {
                        type = ContactsContract.CommonDataKinds.Phone.CONTENT_TYPE
                    }
                    startActivityForResult(intent, 1001)
                } catch (e: Exception) {
                    Log.e(TAG, "pickContact: launch failed", e)
                    contactPendingResult = null
                    result.error("PICK_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
