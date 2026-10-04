package com.shadowswords.connect

import android.Manifest
import android.app.PendingIntent
import android.content.ClipData
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "connect/room")
        TalkBridge.channel = channel
        InstallStatusReceiver.statusSink = { msg ->
            channel.invokeMethod("installStatus", msg)
        }
        channel.setMethodCallHandler { call, result ->
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
                "arm" -> {
                    val on = call.argument<Boolean>("on") == true
                    if (!on) TalkBridge.releaseKeys()
                    TalkBridge.armed = on
                    result.success(null)
                }
                "keysGranted" -> result.success(keysGranted())
                "overlayGranted" -> result.success(Settings.canDrawOverlays(this))
                "openKeys" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "openOverlay" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success(null)
                }
                "bubble" -> {
                    val text = call.argument<String>("text") ?: "Hold to talk"
                    BubbleOverlay.show(this, text)
                    result.success(null)
                }
                "bubbleHide" -> {
                    BubbleOverlay.hide()
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path") ?: ""
                    result.success(installApk(path))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        InstallStatusReceiver.statusSink = null
        super.onDestroy()
    }

    private fun installApk(path: String): String {
        val file = File(path)
        if (!file.exists()) return "missing"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return "needPermission"
        }
        return try {
            val installer = packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            val sessionId = installer.createSession(params)
            val session = installer.openSession(sessionId)
            session.openWrite("package", 0, file.length()).use { output ->
                file.inputStream().use { input -> input.copyTo(output) }
                session.fsync(output)
            }
            val statusIntent = Intent(this, InstallStatusReceiver::class.java).apply {
                action = installStatusAction
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            val pending = PendingIntent.getBroadcast(this, sessionId, statusIntent, flags)
            session.commit(pending.intentSender)
            session.close()
            "ok"
        } catch (_: Exception) {
            try {
                val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    clipData = ClipData.newRawUri("", uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                "fallback_ok"
            } catch (fallback: Exception) {
                "installer: ${fallback.javaClass.simpleName}"
            }
        }
    }

    private fun keysGranted(): Boolean {
        val master = Settings.Secure.getInt(
            contentResolver,
            Settings.Secure.ACCESSIBILITY_ENABLED,
            0,
        ) == 1
        if (!master) return false
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val mine = ComponentName(this, VolumeTalkService::class.java).flattenToString()
        return enabled.split(':').any { it.equals(mine, ignoreCase = true) }
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
        private const val installStatusAction = "com.shadowswords.connect.PACKAGE_INSTALL_STATUS"
    }
}
