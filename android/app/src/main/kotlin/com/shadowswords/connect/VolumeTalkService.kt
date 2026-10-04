package com.shadowswords.connect

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

/**
 * While Connect is behind a game, the volume keys are hold-to-talk.
 * The service does not read the screen. Keys pass through when it is not armed.
 */
class VolumeTalkService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = serviceInfo ?: return
        info.flags = info.flags or AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
        serviceInfo = info
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (!TalkBridge.armed) return false
        val code = event.keyCode
        if (code != KeyEvent.KEYCODE_VOLUME_UP && code != KeyEvent.KEYCODE_VOLUME_DOWN) {
            return false
        }
        when (event.action) {
            KeyEvent.ACTION_DOWN -> {
                if (event.repeatCount == 0) TalkBridge.volumeDownEdge()
                return true
            }
            KeyEvent.ACTION_UP -> {
                TalkBridge.volumeUpEdge()
                return true
            }
        }
        return true
    }

    override fun onDestroy() {
        TalkBridge.releaseKeys()
        super.onDestroy()
    }
}
