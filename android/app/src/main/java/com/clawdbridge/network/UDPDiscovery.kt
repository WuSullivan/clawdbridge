package com.clawdbridge.network

import kotlinx.coroutines.*
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/// UDP 广播发现引擎：发送广播宣告本机 → 监听其他设备广播 → 发现局域网设备
object UDPDiscovery {
    private const val BROADCAST_PORT = 45454
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var socket: DatagramSocket? = null
    private var isRunning = false

    data class DiscoveredDevice(
        val deviceID: String,
        val deviceName: String,
        val platform: String,
        val ipAddress: String
    )

    var onDeviceDiscovered: ((DiscoveredDevice) -> Unit)? = null

    // ── 广播本机信息 ──

    fun broadcast(deviceID: String, deviceName: String) {
        scope.launch {
            try {
                val socket = DatagramSocket().apply { broadcast = true }
                val announce = """{"type":"announce","deviceID":"$deviceID","deviceName":"$deviceName","platform":"android"}"""
                val data = announce.toByteArray(Charsets.UTF_8)

                val packet = DatagramPacket(
                    data, data.size,
                    InetAddress.getByName("255.255.255.255"),
                    BROADCAST_PORT
                )
                socket.send(packet)
                socket.close()
                android.util.Log.d("ClawdBridge", "UDP broadcast sent")
            } catch (e: Exception) {
                android.util.Log.w("ClawdBridge", "UDP broadcast failed: ${e.message}")
            }
        }
    }

    // ── 监听其他设备广播 ──

    fun startListening(deviceID: String, deviceName: String) {
        if (isRunning) return
        isRunning = true

        scope.launch {
            try {
                socket = DatagramSocket(BROADCAST_PORT).also {
                    it.broadcast = true
                    it.reuseAddress = true
                }
                val buffer = ByteArray(1024)

                android.util.Log.i("ClawdBridge", "UDP discovery listening on $BROADCAST_PORT")

                while (isActive && isRunning) {
                    try {
                        val packet = DatagramPacket(buffer, buffer.size)
                        socket?.receive(packet)

                        val json = String(packet.data, 0, packet.length, Charsets.UTF_8)
                        val obj = org.json.JSONObject(json)

                        if (obj.getString("type") == "announce") {
                            val discovered = DiscoveredDevice(
                                deviceID = obj.getString("deviceID"),
                                deviceName = obj.optString("deviceName", "Unknown"),
                                platform = obj.optString("platform", "unknown"),
                                ipAddress = packet.address.hostAddress
                            )
                            // Ignore self-announcements
                            if (discovered.deviceID != deviceID) {
                                onDeviceDiscovered?.invoke(discovered)
                                android.util.Log.i("ClawdBridge",
                                    "Discovered: ${discovered.deviceName} [${discovered.deviceID}]")
                            }
                        }
                    } catch (e: Exception) {
                        if (isActive) {
                            android.util.Log.w("ClawdBridge", "UDP receive error: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("ClawdBridge", "UDP listener error: ${e.message}")
            }
        }

        // 定期广播本机
        scope.launch {
            while (isActive && isRunning) {
                delay(30_000) // 每 30 秒广播一次
                broadcast(deviceID, deviceName)
            }
        }
    }

    fun stop() {
        isRunning = false
        try { socket?.close() } catch (_: Exception) {}
        socket = null
    }
}
