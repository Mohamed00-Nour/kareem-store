package com.kareemham.store

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.OutputStream
import java.util.UUID

/**
 * Reliable Bluetooth thermal printer bridge (SPP + RFCOMM channel 1 fallback).
 * Used instead of the stock plugin connect path which often fails on paired printers.
 */
class BluetoothThermalHandler(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "KareemThermalBT"
        private const val CHANNEL = "kareem.store/thermal_bt"
        private val SPP_UUID: UUID =
            UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private var outputStream: OutputStream? = null
    private var activeSocket: BluetoothSocket? = null
    private var lastMac: String = ""

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        closeConnection()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ispermissionbluetoothgranted" -> {
                if (Build.VERSION.SDK_INT < 31) {
                    result.success(true)
                } else {
                    result.success(
                        ContextCompat.checkSelfPermission(
                            context,
                            Manifest.permission.BLUETOOTH_CONNECT,
                        ) == PackageManager.PERMISSION_GRANTED,
                    )
                }
            }

            "bluetoothenabled" -> {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                result.success(adapter != null && adapter.isEnabled)
            }

            "pairedbluetooths" -> {
                result.success(listPairedDevices())
            }

            "connectionstatus" -> {
                result.success(isSocketAlive())
            }

            "disconnect" -> {
                closeConnection()
                result.success(true)
            }

            "connect" -> {
                val mac = normalizeMac(call.arguments?.toString().orEmpty())
                if (mac.isEmpty()) {
                    result.success(false)
                    return
                }
                CoroutineScope(Dispatchers.Main).launch {
                    val ok = withContext(Dispatchers.IO) { openConnection(mac) }
                    result.success(ok)
                }
            }

            "writebytes" -> {
                @Suppress("UNCHECKED_CAST")
                val bytes = (call.arguments as? List<Int>)?.map { it.toByte() }?.toByteArray()
                if (bytes == null || outputStream == null) {
                    result.success(false)
                    return
                }
                try {
                    outputStream?.write(bytes)
                    outputStream?.flush()
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "writebytes: ${e.message}")
                    closeConnection()
                    result.success(false)
                }
            }

            "printstring" -> {
                val payload = call.arguments?.toString().orEmpty()
                if (outputStream == null) {
                    result.success(false)
                    return
                }
                try {
                    val parts = payload.split("///", limit = 2)
                    var size = 2
                    var text = payload
                    if (parts.size == 2) {
                        size = parts[0].toIntOrNull()?.coerceIn(1, 5) ?: 2
                        text = parts[1]
                    }
                    val stream = outputStream!!
                    stream.write(byteArrayOf(0x1d, 0x21, 0x00))
                    stream.write(byteArrayOf(0x1C, 0x2E))
                    stream.write(byteArrayOf(0x1B, 0x74, 0x10))
                    stream.write(escPosSizeBytes(size))
                    stream.write(text.toByteArray(charset("ISO-8859-1")))
                    stream.flush()
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "printstring: ${e.message}")
                    closeConnection()
                    result.success(false)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun normalizeMac(raw: String): String {
        return raw.trim().uppercase()
    }

    private fun listPairedDevices(): List<String> {
        val items = mutableListOf<String>()
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return items
        val bonded = adapter.bondedDevices ?: return items
        for (device in bonded) {
            val name = device.name ?: "Unknown"
            val address = device.address ?: continue
            items.add("$name#$address")
        }
        return items
    }

    private fun isSocketAlive(): Boolean {
        val stream = outputStream ?: return false
        return try {
            stream.write(" ".toByteArray())
            stream.flush()
            true
        } catch (e: Exception) {
            closeConnection()
            false
        }
    }

    private fun closeConnection() {
        try {
            outputStream?.close()
        } catch (_: Exception) {
        }
        try {
            activeSocket?.close()
        } catch (_: Exception) {
        }
        outputStream = null
        activeSocket = null
    }

    private fun openConnection(mac: String): Boolean {
        closeConnection()
        lastMac = mac

        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null || !adapter.isEnabled) {
            Log.w(TAG, "Bluetooth adapter off")
            return false
        }

        val device: BluetoothDevice = try {
            adapter.getRemoteDevice(mac)
        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "Invalid MAC: $mac")
            return false
        }

        adapter.cancelDiscovery()

        val socket = connectSocket(adapter, device) ?: return false
        return try {
            activeSocket = socket
            outputStream = socket.outputStream
            Log.i(TAG, "Connected to $mac")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Output stream failed: ${e.message}")
            try {
                socket.close()
            } catch (_: Exception) {
            }
            false
        }
    }

    private fun connectSocket(adapter: BluetoothAdapter, device: BluetoothDevice): BluetoothSocket? {
        // 1) Standard SPP UUID (most 58/80mm ESC/POS printers)
        try {
            val socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
            socket.connect()
            if (socket.isConnected) {
                Log.i(TAG, "Connected via SPP UUID")
                return socket
            }
            socket.close()
        } catch (e: Exception) {
            Log.w(TAG, "SPP UUID failed: ${e.message}")
        }

        // 2) Hidden RFCOMM channel 1 — fixes many printers that pair but refuse UUID socket
        try {
            val method = device.javaClass.getMethod(
                "createRfcommSocket",
                Int::class.javaPrimitiveType,
            )
            val socket = method.invoke(device, 1) as BluetoothSocket
            adapter.cancelDiscovery()
            socket.connect()
            if (socket.isConnected) {
                Log.i(TAG, "Connected via RFCOMM channel 1")
                return socket
            }
            socket.close()
        } catch (e: Exception) {
            Log.w(TAG, "RFCOMM ch1 failed: ${e.message}")
        }

        // 3) Reflection on createRfcommSocket with channel 1 via BluetoothDevice
        try {
            val socket = device.javaClass
                .getDeclaredMethod("createInsecureRfcommSocketToServiceRecord", UUID::class.java)
                .invoke(device, SPP_UUID) as BluetoothSocket
            adapter.cancelDiscovery()
            socket.connect()
            if (socket.isConnected) {
                Log.i(TAG, "Connected via insecure SPP")
                return socket
            }
            socket.close()
        } catch (e: Exception) {
            Log.w(TAG, "Insecure SPP failed: ${e.message}")
        }

        return null
    }

    private fun escPosSizeBytes(size: Int): ByteArray {
        return when (size) {
            1 -> byteArrayOf(0x1b, 0x4d, 0x01)
            2 -> byteArrayOf(0x1b, 0x4d, 0x00)
            3 -> byteArrayOf(0x1d, 0x21, 0x11)
            4 -> byteArrayOf(0x1d, 0x21, 0x22)
            5 -> byteArrayOf(0x1d, 0x21, 0x33)
            else -> byteArrayOf(0x1b, 0x4d, 0x00)
        }
    }
}
