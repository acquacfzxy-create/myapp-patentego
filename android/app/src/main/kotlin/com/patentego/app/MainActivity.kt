package com.patentego.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val downloadPreflightChannel = "com.patentego.app/download_preflight"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            downloadPreflightChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method != "getDownloadEnvironment") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val availableBytes = try {
                StatFs(filesDir.absolutePath).availableBytes
            } catch (_: Exception) {
                null
            }
            result.success(
                mapOf(
                    "connectionType" to currentConnectionType(),
                    "availableStorageBytes" to availableBytes,
                ),
            )
        }
    }

    private fun currentConnectionType(): String {
        val manager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = manager.activeNetwork ?: return "offline"
        val capabilities = manager.getNetworkCapabilities(network) ?: return "unknown"
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            else -> "unknown"
        }
    }
}
