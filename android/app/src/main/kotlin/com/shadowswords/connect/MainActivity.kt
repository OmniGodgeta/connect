package com.shadowswords.connect

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingNotify: MethodChannel.Result? = null

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notifyRequest) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingNotify?.success(granted)
        pendingNotify = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "connect/room")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "notifications" -> requestNotifications(result)
                    "start", "update" -> {
                        val text = call.argument<String>("text") ?: "In the room"
                        val intent = Intent(this, RoomService::class.java).putExtra("text", text)
                        try {
                            ContextCompat.startForegroundService(this, intent)
                            result.success(true)
                        } catch (error: Exception) {
                            result.success(false)
                        }
                    }
                    "stop" -> {
                        stopService(Intent(this, RoomService::class.java))
                        result.success(null)
                    }
                    "background" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33) {
            result.success(true)
            return
        }
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(true)
            return
        }
        pendingNotify = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notifyRequest)
    }

    companion object {
        private const val notifyRequest = 4101
    }
}
