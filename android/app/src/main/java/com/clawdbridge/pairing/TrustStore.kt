package com.clawdbridge.pairing

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/// 信任存储：保存已配对设备和加密密钥
object TrustStore {
    private const val PREFS_NAME = "clawdbridge_trust"

    data class TrustEntry(
        val deviceID: String,
        val deviceName: String,
        val platform: String,
        val sharedKey: ByteArray, // AES-256 key
        val pairedAt: Long
    )

    private fun getPrefs(): SharedPreferences =
        androidx.preference.PreferenceManager.getDefaultSharedPreferences(
            com.clawdbridge.ClawdBridgeApp.instance
        )

    fun addEntry(entry: TrustEntry) {
        getPrefs().edit().putString(
            "trust_${entry.deviceID}",
            JSONObject().apply {
                put("deviceID", entry.deviceID)
                put("deviceName", entry.deviceName)
                put("platform", entry.platform)
                put("sharedKey", android.util.Base64.encodeToString(entry.sharedKey, android.util.Base64.NO_WRAP))
                put("pairedAt", entry.pairedAt)
            }.toString()
        ).apply()
    }

    fun getEntry(deviceID: String): TrustEntry? {
        val json = getPrefs().getString("trust_$deviceID", null) ?: return null
        val obj = JSONObject(json)
        return TrustEntry(
            deviceID = obj.getString("deviceID"),
            deviceName = obj.getString("deviceName"),
            platform = obj.getString("platform"),
            sharedKey = android.util.Base64.decode(obj.getString("sharedKey"), android.util.Base64.NO_WRAP),
            pairedAt = obj.getLong("pairedAt")
        )
    }

    fun isTrusted(deviceID: String): Boolean = getPrefs().contains("trust_$deviceID")

    fun removeEntry(deviceID: String) {
        getPrefs().edit().remove("trust_$deviceID").apply()
    }
}
