package com.shadowswords.connect

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

/** A small card over other apps. The Talk control holds the floor. */
object BubbleOverlay {
    private var window: WindowManager? = null
    private var view: LinearLayout? = null
    private var label: TextView? = null
    private var params: WindowManager.LayoutParams? = null

    fun show(context: Context, text: String) {
        if (!Settings.canDrawOverlays(context)) return
        val current = label
        if (current != null) {
            current.text = text
            current.contentDescription = text
            view?.contentDescription = text
            return
        }
        val app = context.applicationContext
        val wm = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val density = app.resources.displayMetrics.density
        val title = TextView(app).apply {
            this.text = text
            contentDescription = text
            setTextColor(0xFFE7F7FB.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            maxLines = 1
            minWidth = (88 * density).toInt()
            maxWidth = (160 * density).toInt()
        }
        val talk = TextView(app).apply {
            this.text = "Talk"
            contentDescription = "Talk"
            setTextColor(0xFF042026.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFF3EE7F5.toInt())
            }
            val size = (52 * density).toInt()
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                marginStart = (10 * density).toInt()
            }
        }
        val card = LinearLayout(app).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            val pad = (12 * density).toInt()
            setPadding(pad, pad / 2, pad / 2, pad / 2)
            background = GradientDrawable().apply {
                cornerRadius = 28 * density
                setColor(0xF0111827.toInt())
                setStroke((density * 1.5f).toInt().coerceAtLeast(1), 0xFF3EE7F5.toInt())
            }
            contentDescription = text
            addView(title)
            addView(talk)
        }
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val layout = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = (16 * density).toInt()
            y = (120 * density).toInt()
        }
        window = wm
        view = card
        label = title
        params = layout
        var originX = 0f
        var originY = 0f
        var startX = 0
        var startY = 0
        title.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    originX = event.rawX
                    originY = event.rawY
                    startX = layout.x
                    startY = layout.y
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    layout.x = startX - (event.rawX - originX).toInt()
                    layout.y = startY + (event.rawY - originY).toInt()
                    try {
                        wm.updateViewLayout(card, layout)
                    } catch (_: Exception) {
                    }
                    true
                }
                else -> true
            }
        }
        talk.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> TalkBridge.bubble(true)
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> TalkBridge.bubble(false)
            }
            true
        }
        try {
            wm.addView(card, layout)
        } catch (_: Exception) {
            window = null
            view = null
            label = null
            params = null
        }
    }

    fun hide() {
        val host = window
        val shown = view
        window = null
        view = null
        label = null
        params = null
        if (host != null && shown != null) {
            try {
                host.removeView(shown)
            } catch (_: Exception) {
            }
        }
        TalkBridge.bubble(false)
    }
}
