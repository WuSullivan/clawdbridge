package com.clawdbridge

import android.app.Application

/// Application 入口：初始化全局组件
class ClawdBridgeApp : Application() {
    lateinit var bridgeService: BridgeServiceManager

    override fun onCreate() {
        super.onCreate()
        instance = this
        bridgeService = BridgeServiceManager()
        android.util.Log.i("ClawdBridge", "Application initialized")
    }

    /// Service 管理器
    class BridgeServiceManager {
        var isRunning: Boolean = false

        fun startService() {
            if (isRunning) return
            // Service 启动逻辑
            android.util.Log.i("ClawdBridge", "Service starting...")
            isRunning = true
        }

        fun stopService() {
            android.util.Log.i("ClawdBridge", "Service stopping...")
            isRunning = false
        }
    }

    companion object {
        lateinit var instance: ClawdBridgeApp
            private set
    }
}
