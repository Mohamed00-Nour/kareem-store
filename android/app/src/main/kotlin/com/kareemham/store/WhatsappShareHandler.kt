package com.kareemham.store

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class WhatsappShareHandler(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "KareemWhatsapp"
        private const val CHANNEL = "kareem.store/whatsapp"
        private val WHATSAPP_PACKAGES = listOf("com.whatsapp", "com.whatsapp.w4b")
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareImage" -> {
                val phone = call.argument<String>("phone").orEmpty()
                val path = call.argument<String>("path").orEmpty()
                val text = call.argument<String>("text").orEmpty()
                result.success(shareImage(phone, path, text))
            }
            "shareImages" -> {
                val phone = call.argument<String>("phone").orEmpty()
                @Suppress("UNCHECKED_CAST")
                val paths = call.argument<List<String>>("paths") ?: emptyList()
                val text = call.argument<String>("text").orEmpty()
                result.success(shareImages(phone, paths, text))
            }
            else -> result.notImplemented()
        }
    }

    private fun shareImage(phone: String, path: String, text: String): Boolean {
        if (path.isBlank()) return false
        return shareImages(phone, listOf(path), text)
    }

    private fun shareImages(phone: String, paths: List<String>, text: String): Boolean {
        val uris = ArrayList<Uri>()
        for (path in paths) {
            if (path.isBlank()) continue
            val file = File(path)
            if (!file.exists()) {
                Log.w(TAG, "Image file not found: $path")
                continue
            }
            try {
                uris.add(
                    FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileProvider",
                        file,
                    ),
                )
            } catch (e: Exception) {
                Log.e(TAG, "FileProvider failed for $path: ${e.message}")
            }
        }
        if (uris.isEmpty()) return false

        val digits = phone.replace(Regex("[^0-9]"), "")
        val jid = if (digits.isNotEmpty()) "${digits}@s.whatsapp.net" else null

        for (packageName in WHATSAPP_PACKAGES) {
            if (tryShare(packageName, uris, text, jid)) return true
        }
        return false
    }

    private fun tryShare(
        packageName: String,
        uris: ArrayList<Uri>,
        text: String,
        jid: String?,
    ): Boolean {
        return try {
            val intent = if (uris.size == 1) {
                Intent(Intent.ACTION_SEND).apply {
                    type = "image/png"
                    putExtra(Intent.EXTRA_STREAM, uris.first())
                }
            } else {
                Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                    type = "image/png"
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                }
            }.apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                setPackage(packageName)
                if (text.isNotEmpty()) {
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                if (jid != null) {
                    putExtra("jid", jid)
                }
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.w(TAG, "share via $packageName failed: ${e.message}")
            false
        }
    }
}
