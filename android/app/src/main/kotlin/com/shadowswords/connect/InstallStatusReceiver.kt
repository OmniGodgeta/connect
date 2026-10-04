package com.shadowswords.connect

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/**
 * Receives PackageInstaller session results.
 *
 * Android 14 blocks a system PendingIntent that starts an activity, so the
 * confirm step arrives here as a broadcast and this receiver opens it.
 */
class InstallStatusReceiver : BroadcastReceiver() {
    companion object {
        var statusSink: ((String) -> Unit)? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm == null) {
                    statusSink?.invoke("installer: no confirmation intent")
                    return
                }
                context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            PackageInstaller.STATUS_SUCCESS -> Unit
            else -> {
                val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                if (status != PackageInstaller.STATUS_FAILURE_ABORTED) {
                    statusSink?.invoke("installer: ${msg ?: "status $status"}")
                }
            }
        }
    }
}
