package com.kareemham.store

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.IOException
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bluetooth thermal printer bridge with permission checks and RFCOMM fallbacks.
 * Supports 58mm / 80mm paper width and Arabic text via raster bitmap (Amiri font).
 */
class BluetoothThermalHandler(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "KareemThermalBT"
        private const val CHANNEL = "kareem.store/thermal_bt"
        private const val CONNECT_TIMEOUT_MS = 15_000L
        private val SPP_UUID: UUID =
            UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var outputStream: OutputStream? = null
    private var activeSocket: BluetoothSocket? = null
    private val isConnecting = AtomicBoolean(false)
    private var configuredPaperMm: Int? = null
    private var arabicTypeface: Typeface? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        closeConnection()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "ispermissionbluetoothgranted" -> {
                    result.success(hasBluetoothPermission())
                }

                "bluetoothenabled" -> {
                    val adapter = getAdapter()
                    result.success(adapter != null && adapter.isEnabled)
                }

                "pairedbluetooths" -> {
                    if (!hasBluetoothPermission()) {
                        result.success(emptyList<String>())
                        return
                    }
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
                    if (!hasBluetoothPermission()) {
                        Log.w(TAG, "connect denied: missing BLUETOOTH_CONNECT")
                        result.success(false)
                        return
                    }
                    if (!isConnecting.compareAndSet(false, true)) {
                        Log.w(TAG, "connect already in progress")
                        result.success(false)
                        return
                    }
                    scope.launch {
                        try {
                            val ok = withContext(Dispatchers.IO) {
                                withTimeout(CONNECT_TIMEOUT_MS) {
                                    openConnection(mac)
                                }
                            }
                            safeSuccess(result, ok)
                        } catch (e: Throwable) {
                            Log.e(TAG, "connect failed: ${e.message}", e)
                            closeConnection()
                            safeSuccess(result, false)
                        } finally {
                            isConnecting.set(false)
                        }
                    }
                }

                "initpaper" -> {
                    val paperMm = (call.arguments as? Number)?.toInt() ?: 80
                    if (outputStream == null) {
                        result.success(false)
                        return
                    }
                    try {
                        applyPaperLayout(outputStream!!, paperMm, force = true)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "initpaper: ${e.message}")
                        closeConnection()
                        result.success(false)
                    }
                }

                "writebytes" -> {
                    @Suppress("UNCHECKED_CAST")
                    val bytes =
                        (call.arguments as? List<Int>)?.map { it.toByte() }?.toByteArray()
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
                        val (size, paperMm, text) = parsePrintPayload(payload)
                        val stream = outputStream!!
                        applyPaperLayout(stream, paperMm)
                        if (needsBitmapRendering(text)) {
                            printTextAsBitmap(stream, text, paperMm, size)
                        } else {
                            printAsciiText(stream, text, size)
                        }
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
        } catch (e: Throwable) {
            Log.e(TAG, "onMethodCall crash: ${e.message}", e)
            safeSuccess(result, false)
        }
    }

    private data class PrintPayload(val size: Int, val paperMm: Int, val text: String)

    private fun parsePrintPayload(payload: String): PrintPayload {
        val parts = payload.split("///", limit = 3)
        return when (parts.size) {
            3 -> PrintPayload(
                size = parts[0].toIntOrNull()?.coerceIn(1, 5) ?: 2,
                paperMm = parts[1].toIntOrNull()?.let { if (it <= 58) 58 else 80 } ?: 80,
                text = parts[2],
            )
            2 -> PrintPayload(
                size = parts[0].toIntOrNull()?.coerceIn(1, 5) ?: 2,
                paperMm = 80,
                text = parts[1],
            )
            else -> PrintPayload(size = 2, paperMm = 80, text = payload)
        }
    }

    private fun safeSuccess(result: MethodChannel.Result, value: Boolean) {
        try {
            result.success(value)
        } catch (e: IllegalStateException) {
            Log.w(TAG, "result already submitted: ${e.message}")
        }
    }

    private fun hasBluetoothPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return true
        }
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun getAdapter(): BluetoothAdapter? {
        val manager =
            context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter ?: BluetoothAdapter.getDefaultAdapter()
    }

    private fun normalizeMac(raw: String): String {
        return raw.trim().uppercase()
    }

    private fun printWidthDots(paperMm: Int): Int = if (paperMm <= 58) 384 else 576

    private fun applyPaperLayout(stream: OutputStream, paperMm: Int, force: Boolean = false) {
        if (!force && configuredPaperMm == paperMm) return
        stream.write(byteArrayOf(0x1B, 0x40))
        val dots = printWidthDots(paperMm)
        stream.write(
            byteArrayOf(
                0x1D,
                0x57,
                (dots and 0xFF).toByte(),
                ((dots shr 8) and 0xFF).toByte(),
            ),
        )
        stream.write(byteArrayOf(0x1D, 0x4C, 0x00, 0x00))
        configuredPaperMm = paperMm
    }

    private fun getArabicTypeface(): Typeface {
        arabicTypeface?.let { return it }
        val assetPaths = listOf(
            "flutter_assets/fonts/Amiri-Regular.ttf",
            "flutter_assets/fonts/Cairo-Medium.ttf",
        )
        for (path in assetPaths) {
            try {
                val tf = Typeface.createFromAsset(context.assets, path)
                arabicTypeface = tf
                return tf
            } catch (e: Exception) {
                Log.w(TAG, "Font not found at $path: ${e.message}")
            }
        }
        Log.w(TAG, "Using default typeface for Arabic — bundle Amiri in pubspec.yaml")
        return Typeface.DEFAULT
    }

    private fun needsBitmapRendering(text: String): Boolean {
        return text.any { ch ->
            ch.code > 0x7E || Character.UnicodeBlock.of(ch) == Character.UnicodeBlock.ARABIC
        }
    }

    private fun textSizePx(escSize: Int, paperMm: Int): Float {
        val base = if (paperMm <= 58) 22f else 26f
        return when (escSize) {
            1 -> base
            2 -> base + 4f
            3 -> base + 10f
            4 -> base + 16f
            5 -> base + 22f
            else -> base + 4f
        }
    }

    private fun printAsciiText(stream: OutputStream, text: String, size: Int) {
        stream.write(byteArrayOf(0x1d, 0x21, 0x00))
        stream.write(byteArrayOf(0x1B, 0x74, 0x00))
        stream.write(escPosSizeBytes(size))
        stream.write(text.toByteArray(Charsets.ISO_8859_1))
    }

    private fun printTextAsBitmap(
        stream: OutputStream,
        text: String,
        paperMm: Int,
        size: Int,
    ) {
        val bitmap = renderTextBitmap(text, paperMm, textSizePx(size, paperMm))
        printBitmapEscPos(stream, bitmap)
        if (!bitmap.isRecycled) {
            bitmap.recycle()
        }
    }

    private fun renderTextBitmap(text: String, paperMm: Int, textSizePx: Float): Bitmap {
        val widthDots = printWidthDots(paperMm)
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = getArabicTypeface()
            this.textSize = textSizePx
            color = Color.BLACK
        }

        val layout = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            StaticLayout.Builder.obtain(text, 0, text.length, paint, widthDots)
                .setAlignment(Layout.Alignment.ALIGN_OPPOSITE)
                .setTextDirection(TextDirectionHeuristics.FIRSTSTRONG_LTR)
                .setIncludePad(false)
                .build()
        } else {
            @Suppress("DEPRECATION")
            StaticLayout(
                text,
                paint,
                widthDots,
                Layout.Alignment.ALIGN_OPPOSITE,
                1f,
                0f,
                false,
            )
        }

        val height = layout.height.coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(widthDots, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        canvas.save()
        canvas.translate(0f, 0f)
        layout.draw(canvas)
        canvas.restore()
        return bitmap
    }

    private fun printBitmapEscPos(stream: OutputStream, bitmap: Bitmap) {
        val width = bitmap.width
        val height = bitmap.height
        var y = 0
        val sliceHeight = 24
        while (y < height) {
            stream.write(byteArrayOf(0x1B, 0x2A, 33))
            stream.write(
                byteArrayOf(
                    (width and 0xFF).toByte(),
                    ((width shr 8) and 0xFF).toByte(),
                ),
            )
            for (x in 0 until width) {
                for (k in 0 until 3) {
                    var slice = 0
                    for (b in 0 until 8) {
                        val yPos = y + k * 8 + b
                        if (yPos < height) {
                            val pixel = bitmap.getPixel(x, yPos)
                            val luminance =
                                (Color.red(pixel) + Color.green(pixel) + Color.blue(pixel)) / 3
                            if (luminance < 160) {
                                slice = slice or (1 shl (7 - b))
                            }
                        }
                    }
                    stream.write(slice)
                }
            }
            stream.write(byteArrayOf(0x0A))
            y += sliceHeight
        }
    }

    @SuppressLint("MissingPermission")
    private fun listPairedDevices(): List<String> {
        val items = mutableListOf<String>()
        val adapter = getAdapter() ?: return items
        if (!adapter.isEnabled) return items
        val bonded: Set<BluetoothDevice> = try {
            adapter.bondedDevices ?: emptySet()
        } catch (e: SecurityException) {
            Log.e(TAG, "bondedDevices SecurityException: ${e.message}")
            return items
        }
        for (device in bonded) {
            try {
                val name = device.name ?: "Printer"
                val address = device.address ?: continue
                if (address.isBlank()) continue
                items.add("$name#$address")
            } catch (e: SecurityException) {
                Log.w(TAG, "device name SecurityException: ${e.message}")
            }
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
        configuredPaperMm = null
    }

    @SuppressLint("MissingPermission")
    private fun openConnection(mac: String): Boolean {
        closeConnection()

        val adapter = getAdapter()
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

        try {
            adapter.cancelDiscovery()
        } catch (e: SecurityException) {
            Log.w(TAG, "cancelDiscovery: ${e.message}")
        }

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

    @SuppressLint("MissingPermission")
    private fun connectSocket(
        adapter: BluetoothAdapter,
        device: BluetoothDevice,
    ): BluetoothSocket? {
        val attempts = listOf(
            { createRfcommChannel1(device) },
            { createSppSocket(device) },
            { createInsecureSppSocket(device) },
        )

        for (attempt in attempts) {
            var socket: BluetoothSocket? = null
            try {
                socket = attempt()
                if (socket == null) continue
                try {
                    adapter.cancelDiscovery()
                } catch (_: SecurityException) {
                }
                socket.connect()
                if (socket.isConnected) {
                    return socket
                }
                socket.close()
            } catch (e: IOException) {
                Log.w(TAG, "socket connect IOException: ${e.message}")
                try {
                    socket?.close()
                } catch (_: Exception) {
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "socket connect SecurityException: ${e.message}")
                try {
                    socket?.close()
                } catch (_: Exception) {
                }
                return null
            } catch (e: Exception) {
                Log.w(TAG, "socket connect failed: ${e.message}")
                try {
                    socket?.close()
                } catch (_: Exception) {
                }
            }
        }
        return null
    }

    @SuppressLint("MissingPermission")
    private fun createSppSocket(device: BluetoothDevice): BluetoothSocket? {
        return device.createRfcommSocketToServiceRecord(SPP_UUID)
    }

    @SuppressLint("MissingPermission")
    private fun createRfcommChannel1(device: BluetoothDevice): BluetoothSocket? {
        val method = device.javaClass.getMethod(
            "createRfcommSocket",
            Int::class.javaPrimitiveType,
        )
        return method.invoke(device, 1) as? BluetoothSocket
    }

    @SuppressLint("MissingPermission")
    private fun createInsecureSppSocket(device: BluetoothDevice): BluetoothSocket? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.GINGERBREAD_MR1) {
            device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
        } else {
            null
        }
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
