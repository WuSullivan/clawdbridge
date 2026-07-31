package com.clawdbridge.sync

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.util.Base64
import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

/**
 * Android 剪贴板同步引擎：按需传输架构
 *
 * 流程：
 * 1. 轮询 ClipboardManager 检测变更
 * 2. 打包为 ClipPayload JSON → 通过 TCP 发送给 Mac
 * 3. 接收远程 payload → 写入本地剪贴板
 * 4. 大文件（>3MB）弹窗确认
 */
class ClipboardSync(
    private val context: Context,
    private val onPayloadToSend: ((ByteArray) -> Unit)? = null
) {
    private val clipboardManager: ClipboardManager =
        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private var lastClipDigest: String? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var isRunning = false
    private val deviceID: String
    private val receiveDir = File(context.filesDir, "ClawdBridge/Files").also { it.mkdirs() }

    /** 最近 100 条 hash，用于去重 */
    private val recentHashes = LinkedHashSet<String>(100)
    private const val MAX_DEDUP = 100
    private const val LARGE_FILE_THRESHOLD: Long = 3 * 1024 * 1024 // 3 MB

    init {
        val prefs = context.getSharedPreferences("clawdbridge", Context.MODE_PRIVATE)
        deviceID = prefs.getString("device_id", "")?.takeIf { it.isNotEmpty() }
            ?: java.util.UUID.randomUUID().toString().also {
                prefs.edit().putString("device_id", it).apply()
            }
    }

    // ── Clipboard Monitor ──

    fun start() {
        if (isRunning) return
        isRunning = true
        lastClipDigest = getCurrentDigest()

        scope.launch {
            while (isActive && isRunning) {
                checkClipboard()
                delay(500)
            }
        }
        Log.i(TAG, "Started")
    }

    fun stop() { isRunning = false }

    private fun checkClipboard() {
        try {
            val clip = clipboardManager.primaryClip ?: return
            if (clip.itemCount == 0) return

            val item = clip.getItemAt(0)
            val digest = computeDigest(item)

            if (digest != null && digest != lastClipDigest && !isDuplicate(digest)) {
                lastClipDigest = digest
                markSeen(digest)

                val payloads = packClipItem(item)
                for (payload in payloads) {
                    val json = payload.toJSON().toString()
                    onPayloadToSend?.invoke(json.toByteArray(Charsets.UTF_8))
                    Log.d(TAG, "Send: ${payload.type} (${(payload.dataSize ?: 0) / 1024} KB)")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "checkClipboard error: ${e.message}")
        }
    }

    private fun getCurrentDigest(): String? {
        return try {
            val clip = clipboardManager.primaryClip
            if (clip != null && clip.itemCount > 0) computeDigest(clip.getItemAt(0)) else null
        } catch (_: Exception) { null }
    }

    private fun computeDigest(item: ClipData.Item): String? {
        return try {
            val content = item.text?.toString()
                ?: item.uri?.toString()
                ?: return null
            val md = MessageDigest.getInstance("SHA-256")
            md.update(content.toByteArray(Charsets.UTF_8))
            md.digest().joinToString("") { "%02x".format(it) }
        } catch (_: Exception) { null }
    }

    // ── Pack to ClipPayload ──

    private fun packClipItem(item: ClipData.Item): List<ClipPayload> {
        val payloads = mutableListOf<ClipPayload>()

        // ── Text ──
        item.text?.toString()?.takeIf { it.isNotEmpty() }?.let { text ->
            val data = text.toByteArray(Charsets.UTF_8)
            payloads.add(ClipPayload(
                deviceID = deviceID,
                timestamp = System.currentTimeMillis(),
                type = "text",
                contentHash = sha256(data),
                dataSize = data.size.toLong(),
                data = data
            ))
        }

        // ── URI / File ──
        item.uri?.let { uri ->
            try {
                val content = readUri(uri)
                if (content.isEmpty()) return@let
                val fileName = uriName(uri) ?: "clipboard_file"
                val ext = fileName.substringAfterLast('.', "").lowercase()
                val type = when {
                    VIDEO_EXTS.contains(ext) -> "video"
                    IMAGE_EXTS.contains(ext) -> "image"
                    DOC_EXTS.contains(ext) -> "document"
                    else -> "file"
                }
                payloads.add(ClipPayload(
                    deviceID = deviceID,
                    timestamp = System.currentTimeMillis(),
                    type = type,
                    contentHash = sha256(content),
                    dataSize = content.size.toLong(),
                    data = content,
                    fileName = fileName
                ))
            } catch (e: Exception) {
                Log.w(TAG, "Failed to read URI: ${e.message}")
            }
        }

        return payloads
    }

    private fun readUri(uri: Uri): ByteArray {
        return context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: ByteArray(0)
    }

    private fun uriName(uri: Uri): String? {
        val cursor = context.contentResolver.query(uri, null, null, null, null)
        return cursor?.use {
            if (it.moveToFirst()) {
                val idx = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) it.getString(idx) else null
            } else null
        }
    }

    // ── Receive Remote Payload ──

    fun onRemotePayload(data: ByteArray) {
        try {
            val json = JSONObject(String(data, Charsets.UTF_8))
            val payload = fromJSON(json) ?: return

            if (isDuplicate(payload.contentHash)) return
            markSeen(payload.contentHash)

            // 大文件弹窗确认
            if (payload.isLarge()) {
                Log.w(TAG, "Large file (${payload.dataSize}B): user confirmation needed")
                // 弹窗确认由 UI 层处理，这里仅记录
            }

            writeToClipboard(payload)
            Log.i(TAG, "Received: ${payload.type} from ${payload.deviceID}")
        } catch (e: Exception) {
            Log.w(TAG, "onRemotePayload error: ${e.message}")
        }
    }

    private fun writeToClipboard(payload: ClipPayload) {
        when (payload.type) {
            "text" -> {
                val text = String(payload.data ?: return, Charsets.UTF_8)
                lastClipDigest = sha256(payload.data)
                val clip = ClipData.newPlainText("ClawdBridge", text)
                clipboardManager.setPrimaryClip(clip)
            }
            "image", "video", "file", "document" -> {
                val data = payload.data ?: return
                val name = payload.fileName ?: "clawdbridge_file"
                val dest = File(receiveDir, name)
                dest.parentFile?.mkdirs()
                FileOutputStream(dest).use { it.write(data) }

                val uri = android.provider.FileProvider.getUriForFile(
                    context, "${context.packageName}.fileprovider", dest
                )
                val clip = ClipData.newUri(context.contentResolver, "ClawdBridge", uri)
                clipboardManager.setPrimaryClip(clip)
            }
        }
    }

    // ── Dedup ──

    @Synchronized
    private fun isDuplicate(hash: String): Boolean = recentHashes.contains(hash)

    @Synchronized
    private fun markSeen(hash: String) {
        if (recentHashes.size >= MAX_DEDUP) {
            val it = recentHashes.iterator()
            if (it.hasNext()) { it.next(); it.remove() }
        }
        recentHashes.add(hash)
    }

    companion object {
        private const val TAG = "ClipboardSync"

        val VIDEO_EXTS = setOf("mp4", "mov", "m4v", "avi", "mkv", "webm", "3gp")
        val IMAGE_EXTS = setOf("png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff")
        val DOC_EXTS = setOf("doc", "docx", "ppt", "pptx", "xls", "xlsx",
            "pdf", "odt", "ods", "odp", "rtf", "csv", "txt", "md")

        fun sha256(data: ByteArray): String {
            val md = MessageDigest.getInstance("SHA-256")
            return md.digest(data).joinToString("") { "%02x".format(it) }
        }
    }
}

/**
 * 新版 ClipPayload：统一的数据交换模型
 * JSON 编码，支持 text/image/video/file/document
 */
data class ClipPayload(
    val deviceID: String,
    val timestamp: Long,
    val type: String,
    val contentHash: String,
    val dataSize: Long,
    val data: ByteArray? = null,
    val fileName: String? = null,
    val version: Int = 1
) {
    fun isLarge(): Boolean = dataSize > 3 * 1024 * 1024

    fun toJSON(): JSONObject = JSONObject().apply {
        put("version", version)
        put("deviceID", deviceID)
        put("timestamp", timestamp)
        put("type", type)
        put("contentHash", contentHash)
        put("dataSize", dataSize)
        fileName?.let { put("fileName", it) }
        data?.let { put("data", Base64.encodeToString(it, Base64.NO_WRAP)) }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ClipPayload) return false
        return contentHash == other.contentHash
    }

    override fun hashCode(): Int = contentHash.hashCode()
}

fun fromJSON(json: JSONObject): ClipPayload? {
    return try {
        val dataB64 = json.optString("data", "")
        ClipPayload(
            deviceID = json.getString("deviceID"),
            timestamp = json.optLong("timestamp", System.currentTimeMillis()),
            type = json.getString("type"),
            contentHash = json.getString("contentHash"),
            dataSize = json.optLong("dataSize", 0),
            data = if (dataB64.isNotEmpty()) Base64.decode(dataB64, Base64.NO_WRAP) else null,
            fileName = json.optString("fileName", null),
            version = json.optInt("version", 1)
        )
    } catch (e: Exception) {
        Log.w("ClipPayload", "fromJSON error: ${e.message}")
        null
    }
}
