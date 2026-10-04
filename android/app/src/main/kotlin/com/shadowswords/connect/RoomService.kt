package com.shadowswords.connect

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class RoomService : Service() {
    private var wake: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(CHANNEL_ID, "Room", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Shows while Connect is in the room"
            channel.setSound(null, null)
            manager.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra("text") ?: "In the room"
        val notification = build(text)
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                try {
                    startForeground(NOTIF_ID, notification, foregroundType())
                } catch (error: Exception) {
                    startForeground(
                        NOTIF_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                    )
                }
            } else if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(NOTIF_ID, notification)
            }
        } catch (error: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        holdWake()
        return START_STICKY
    }

    override fun onDestroy() {
        TalkBridge.releaseKeys()
        TalkBridge.armed = false
        BubbleOverlay.hide()
        wake?.let { if (it.isHeld) it.release() }
        wake = null
        super.onDestroy()
    }

    private fun foregroundType(): Int {
        val playback = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        val mic = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
        return if (mic) {
            playback or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        } else {
            playback
        }
    }

    private fun holdWake() {
        if (wake?.isHeld == true) return
        val power = getSystemService(POWER_SERVICE) as PowerManager
        wake = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "connect:room").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun build(text: String): Notification {
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_connect)
            .setContentTitle("Connect")
            .setContentText(text)
            .setContentIntent(pending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "connect.room"
        private const val NOTIF_ID = 1
    }
}
