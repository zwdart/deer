package xin.dart.deer

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "xin.dart.deer/mobile",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticast" -> {
                    try {
                        if (multicastLock == null) {
                            val wifi = applicationContext.getSystemService(
                                Context.WIFI_SERVICE,
                            ) as WifiManager
                            multicastLock = wifi.createMulticastLock("deer-multicast").apply {
                                setReferenceCounted(false)
                            }
                        }
                        val lock = multicastLock
                        if (lock != null && !lock.isHeld) lock.acquire()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("multicast", e.message, null)
                    }
                }

                "releaseMulticast" -> {
                    try {
                        multicastLock?.let { if (it.isHeld) it.release() }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("multicast", e.message, null)
                    }
                }

                "getClipboardImage" -> result.success(readClipboardImage())

                "deviceLabel" -> {
                    val manufacturer = Build.MANUFACTURER.orEmpty().trim()
                    val model = Build.MODEL.orEmpty().trim()
                    val label = when {
                        manufacturer.isEmpty() -> model
                        model.startsWith(manufacturer, ignoreCase = true) -> model
                        else -> "$manufacturer $model"
                    }
                    result.success(label.ifEmpty { "Android" })
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun readClipboardImage(): ByteArray? {
        val clipboard = getSystemService(
            Context.CLIPBOARD_SERVICE,
        ) as? ClipboardManager ?: return null
        val clip = clipboard.primaryClip ?: return null
        for (i in 0 until clip.itemCount) {
            val item = clip.getItemAt(i)
            val uri = item.uri ?: item.text?.toString()?.let { raw ->
                if (raw.startsWith("content://") || raw.startsWith("file://")) {
                    Uri.parse(raw)
                } else {
                    null
                }
            } ?: continue
            try {
                val mime = contentResolver.getType(uri)
                    ?: clip.description?.getMimeType(i)
                if (mime != null && !mime.startsWith("image/")) continue
                val bytes = if (uri.scheme == "file") {
                    val path = uri.path ?: continue
                    File(path).readBytes()
                } else {
                    contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        ?: continue
                }
                if (bytes.isNotEmpty()) return bytes
            } catch (_: Exception) {
            }
        }
        return null
    }

    override fun onDestroy() {
        try {
            multicastLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        multicastLock = null
        super.onDestroy()
    }
}
