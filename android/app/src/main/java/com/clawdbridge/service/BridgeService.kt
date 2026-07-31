package com.clawdbridge.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.lifecycle.LifecycleService
import com.clawdbridge.MainActivity
import com.clawdbridge.network.TCPClient
import com.clawdbridge.network.UDPDiscovery
import com.clawdbridge.sync.ClipboardSync
import com.clawdbridge.sync.FileTransfer
import java.io.File

/**
 * Android 前台服务：后台保活 + 剪贴板同步引擎
 * 无声音/震动通知（IMPORTANCE_LOW）
 */
class BridgeService : LifecycleService() {

    companion object {
        const val CHANNEL_ID = "clawdbridge_service"
        const val NOTIFICATION_ID = 1
        private const val TAG = "BridgeService"
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var clipboardSync: ClipboardSync? = null
    private var tcpClient: TCPClient? = null
    private var udpDiscovery: UDPDiscovery? = null
    private var fileTransfer: FileTransfer? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
        Log.i(TAG, "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        Log.i(TAG, "Foreground service started")

        // File transfer cache
        val cacheDir = File(cacheDir, "staged")
        cacheDir.mkdirs()
        fileTransfer = FileTransfer(cacheDir)

        // Clipboard sync → TCP client
        clipboardSync = ClipboardSync(this) { data ->
            tcpClient?.send(data)
        }
        clipboardSync?.start()

        // TCP client for Mac↔Android
        tcpClient = TCPClient()
        tcpClient?.onPayloadReceived = { data ->
            clipboardSync?.onRemotePayload(data)
        }

        // UDP discovery for LAN auto-detection
        udpDiscovery = UDPDiscovery()
        udpDiscovery?.start()

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        clipboardSync?.stop()
        tcpClient?.disconnect()
        udpDiscovery?.stop()
        releaseWakeLock()
        Log.i(TAG, "Service destroyed")
        super.onDestroy()
    }

    // ── Notification ──

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "ClawdBridge 服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "后台剪贴板同步服务"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
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
                .setSilent(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("ClawdBridge")
                .setContentText("剪贴板同步运行中")
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setPriority(Notification.PRIORITY_MIN)
                .build()
        }
    }

    // ── WakeLock ──

    private fun acquireWakeLock() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "ClawdBridge::Wakelock"
        ).apply {
            acquire(10 * 60 * 1000L)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }
}
