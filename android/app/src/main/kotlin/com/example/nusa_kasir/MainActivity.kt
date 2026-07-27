package com.example.nusa_kasir

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.os.Bundle
import android.provider.ContactsContract
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nusa_kasir/contacts"
    private val BT_CHANNEL = "com.nusa_kasir/bluetooth"

    // ── Static (companion) data — survives activity recreation ──
    companion object {
        private const val TAG = "NUSA"
        // Store contact DATA (not MethodChannel.Result!) so it survives
        // even when the activity is destroyed & recreated while the picker is open.
        private var pendingContact: MutableMap<String, String>? = null
    }

    private var contactChannel: MethodChannel? = null
    private var btPendingResult: MethodChannel.Result? = null

    // ── Send any pending contact back to Dart ──
    private fun flushPendingContact() {
        val data = pendingContact ?: return
        pendingContact = null
        contactChannel?.invokeMethod("onContactResult", data)
        Log.d(TAG, "flushPendingContact: sending name='${data["name"]}' phone='${data["phone"]}'")
    }

    @Deprecated("Required for Bluetooth enable — contact picker uses two-way MethodChannel")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        Log.d(TAG, "onActivityResult req=$requestCode res=$resultCode hasData=${data != null}")

        when (requestCode) {
            1001 -> { // Contact picker
                try {
                    if (resultCode != RESULT_OK || data == null) {
                        Log.d(TAG, "Contact picker: user cancelled")
                        pendingContact = null
                        flushPendingContact() // send null signal — Dart times out gracefully
                        return
                    }
                    val uri = data.data
                    if (uri == null) {
                        Log.w(TAG, "Contact picker: data.data is null")
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
                                Log.d(TAG, "Contact picker: SUCCESS name='$name' phone='$phone'")
                                pendingContact = mutableMapOf("name" to name, "phone" to phone)
                                flushPendingContact()
                            } else {
                                Log.w(TAG, "Contact picker: cursor is empty")
                            }
                        }
                    } else {
                        Log.w(TAG, "Contact picker: contentResolver.query returned null cursor")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Contact picker: read failed", e)
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

        // ── Contact picker channel (two-way: Dart↔Native) ──
        contactChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        contactChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickContact" -> {
                    Log.d(TAG, "pickContact: launching contact picker")
                    try {
                        val intent = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI).apply {
                            type = ContactsContract.CommonDataKinds.Phone.CONTENT_TYPE
                        }
                        startActivityForResult(intent, 1001)
                        // Acknowledge immediately — result will be sent via onContactResult invoke
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "pickContact: launch failed", e)
                        result.error("PICK_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ── Flush any pending contact from a previous activity instance ──
        Log.d(TAG, "configureFlutterEngine: checking for pending contact (recreation?)")
        if (pendingContact != null) {
            // Post to next frame so Dart side has time to register its listener
            flutterEngine.dartExecutor.binaryMessenger.send(CHANNEL, null)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                flushPendingContact()
            }, 200)
        }
    }
}
