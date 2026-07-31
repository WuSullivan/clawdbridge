package com.clawdbridge.sync

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/// 剪贴板同步引擎（Android 端）
/// 轮询系统剪贴板变更 → 打包为 JSON → 通过 TCP 发送
/// 接收远程载荷 → 写入本地剪贴板
class ClipboardSync(
    private val context: Context,
    private val onPayloadToSend: ((ByteArray) -> Unit)? = null
) {
    private val clipboardManager: ClipboardManager =
        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private var lastClipText: String? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var isRunning = false
    private val deviceID: String

    // File receive directory
    private val receiveDir: File =
        File(context.filesDir, "received").also { it.mkdirs() }

    init {
        val prefs = androidx.preference.PreferenceManager.getDefaultSharedPreferences(context)
        deviceID = prefs.getString("device_id", android.os.Build.MODEL) ?: android.os.Build.MODEL
    }

    // ── ClipPayload JSON Serialization ──

    private data class ClipPayload(
        val deviceID: String,
        val timestamp: Long,
        val type: String,     // "text" | "file"
        val text: String? = null,
        val fileName: String? = null,
        val fileSize: Long? = null,
        val chunkIndex: Int? = null,
        val totalChunks: Int? = null,
        val chunkData: String? = null  // Base64 encoded
    ) {
        fun toJSON(): JSONObject = JSONObject().apply {
            put("version", 1)
            put("deviceID", deviceID)
            put("timestamp", timestamp)
            put("type", type)
            text?.let { put("data", it.toByteArray(Charsets.UTF_8).let { b64 -> android.util.Base64.encodeToString(b64, android.util.Base64.NO_WRAP) }) }
            fileName?.let { put("fileName", it) }
            fileSize?.let { put("fileSize", it) }
            chunkIndex?.let { put("chunkIndex", it) }
            totalChunks?.let { put("totalChunks", it) }
            chunkData?.let { put("data", it) }
        }

        companion object {
            fun fromJSON(json: JSONObject): ClipPayload {
                val dataField = json.optString("data", null)
                return ClipPayload(
                    deviceID = json.getString("deviceID"),
                    timestamp = json.optLong("timestamp", System.currentTimeMillis()),
                    type = json.getString("type"),
                    fileName = json.optString("fileName", null),
                    fileSize = if (json.has("fileSize")) json.getLong("fileSize") else null,
                    chunkIndex = if (json.has("chunkIndex")) json.getInt("chunkIndex") else null,
                    totalChunks = if (json.has("totalChunks")) json.getInt("totalChunks") else null,
                    chunkData = dataField
                )
            }
        }
    }

    // ── Clipboard Monitor ──

    fun start() {
        if (isRunning) return
        isRunning = true

        // Snapshot current clipboard to avoid initial sync
        lastClipText = getCurrentClipText()

        scope.launch {
            while (isActive && isRunning) {
                checkClipboard()
                delay(500) // Poll every 500ms
            }
        }
        android.util.Log.i("ClipboardSync", "Started")
    }

    fun stop() {
        isRunning = false
    }

    private fun checkClipboard() {
        val currentText = getCurrentClipText()
        if (currentText != null && currentText != lastClipText) {
            lastClipText = currentText
            android.util.Log.d("ClipboardSync", "Clip changed: \"${currentText.take(80)}\"")

            val payload = ClipPayload(
                deviceID = deviceID,
                timestamp = System.currentTimeMillis(),
                type = "text",
                text = currentText
            )
            val json = payload.toJSON().toString()
            onPayloadToSend?.invoke(json.toByteArray(Charsets.UTF_8))
        }
    }

    private fun getCurrentClipText(): String? {
        return try {
            val clip = clipboardManager.primaryClip
            if (clip != null && clip.itemCount > 0) {
                val item = clip.getItemAt(0)
                item.text?.toString() ?: item.uri?.toString()
            } else null
        } catch (e: Exception) {
            null
        }
    }

    // ── Receive Remote Clipboard ──

    fun onRemotePayload(data: ByteArray) {
        try {
            val json = JSONObject(String(data, Charsets.UTF_8))
            val payload = ClipPayload.fromJSON(json)

            when (payload.type) {
                "text" -> {
                    val rawData = payload.chunkData ?: return
                    val text = String(
                        android.util.Base64.decode(rawData, android.util.Base64.NO_WRAP),
                        Charsets.UTF_8
                    )
                    writeClipboard(text)
                    android.util.Log.i("ClipboardSync", "Received text from ${payload.deviceID}")
                }
                // File sync handled by FileTransfer
            }
        } catch (e: Exception) {
            android.util.Log.w("ClipboardSync", "Failed to parse payload: ${e.message}")
        }
    }

    private fun writeClipboard(text: String) {
        lastClipText = text // Prevent echo
        val clip = ClipData.newPlainText("ClawdBridge", text)
        clipboardManager.setPrimaryClip(clip)
    }
}
