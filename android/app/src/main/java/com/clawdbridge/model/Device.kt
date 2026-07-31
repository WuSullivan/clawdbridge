package com.clawdbridge.model

import org.json.JSONObject
import java.net.InetAddress
import java.net.NetworkInterface

/// 设备模型：局域网同步节点
data class Device(
    val deviceID: String,
    val deviceName: String,
    val platform: Platform,
    val ipAddress: String? = null,
    val port: Int = 45455,
    val isTrusted: Boolean = false,
    val lastSeen: Long = System.currentTimeMillis()
) {
    enum class Platform(val raw: String) {
        MAC("mac"),
        IOS("ios"),
        ANDROID("android");

        companion object {
            fun from(raw: String): Platform =
                entries.firstOrNull { it.raw == raw } ?: ANDROID
        }
    }

    companion object {
        /// 获取本机局域网 IPv4 地址
        fun getLocalIP(): String? {
            try {
                NetworkInterface.getNetworkInterfaces()?.toList()?.forEach { iface ->
                    if (iface.isLoopback || !iface.isUp) return@forEach
                    val addrs = iface.inetAddresses ?: return@forEach
                    for (addr in addrs) {
                        if (addr is java.net.Inet4Address && !addr.isLoopbackAddress) {
                            return addr.hostAddress
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("ClawdBridge", "Failed to get local IP", e)
            }
            return null
        }

        /// 本机设备
        fun localDevice(): Device {
            val prefs = android.preference.PreferenceManager.getDefaultSharedPreferences(
                ClawdBridgeApp.instance
            )
            val id = prefs.getString("device_id", null) ?: run {
                val newId = java.util.UUID.randomUUID().toString()
                prefs.edit().putString("device_id", newId).apply()
                newId
            }
            return Device(
                deviceID = id,
                deviceName = android.os.Build.MODEL ?: "Android",
                platform = Platform.ANDROID,
                ipAddress = getLocalIP()
            )
        }
    }
}
