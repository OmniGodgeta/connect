package com.shadowswords.connect

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** Volume keys and the bubble both ask Flutter to hold or release the floor. */
object TalkBridge {
    @Volatile
    var armed: Boolean = false

    var channel: MethodChannel? = null

    private val main = Handler(Looper.getMainLooper())
    private var keysHeld = 0

    fun volumeDownEdge() {
        if (!armed) return
        keysHeld += 1
        if (keysHeld == 1) send("volumeDown")
    }

    fun volumeUpEdge() {
        if (keysHeld > 0) keysHeld -= 1
        if (keysHeld == 0) send("volumeUp")
    }

    fun releaseKeys() {
        val was = keysHeld
        keysHeld = 0
        if (was > 0) send("volumeUp")
    }

    fun bubble(down: Boolean) {
        send(if (down) "bubbleDown" else "bubbleUp")
    }

    private fun send(method: String) {
        val sink = channel ?: return
        main.post {
            try {
                sink.invokeMethod(method, null)
            } catch (_: Exception) {
            }
        }
    }
}
