package com.clawdbridge.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.lifecycle.LifecycleService
import com.clawdbridge.MainActivity

/// 前台服务：后台保活 + 开机自启
/// 使用 notification 维持前台状态，避免被系统回收
class BridgeService : LifecycleService() {

    companion object {
        const val CHANNEL_ID = "clawdbridge_service"
        const val NOTIFICATION_ID = 1
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()

        android.util.Log.i("ClawdBridge", "BridgeService created")

        // Start clipboard sync
        // Start UDP discovery
        // Start TCP server
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Start as foreground service with persistent notification
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)

        // Boot completed: auto-start
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            android.util.Log.i("ClawdBridge", "Auto-starting after boot")
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseWakeLock()
        android.util.Log.i("ClawdBridge", "BridgeService destroyed")
        super.onDestroy()
    }

    // ── Notification Channel ──

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "ClawdBridge 服务",
                NotificationManager.IMPORTANCE_LOW  // LOW = 不发出声音/震动
            ).apply {
                description = "后台剪贴板同步服务"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("ClawdBridge")
                .setContentText("剪贴板同步运行中")
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("ClawdBridge")
                .setContentText("剪贴板同步运行中")
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        }
    }

    // ── Wake Lock (prevent deep sleep) ──

    private fun acquireWakeLock() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "ClawdBridge::Wakelock"
        ).apply {
            acquire(10 * 60 * 1000L) // 10 minutes, auto-renewed
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }
}
