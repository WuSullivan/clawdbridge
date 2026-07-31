package com.clawdbridge.sync

import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/// 文件分块传输管理器（Android 端）
/// 与 Mac 端 FileTransfer 协议对应
/// 块大小：64KB
object FileTransfer {
    private const val CHUNK_SIZE = 64 * 1024 // 64KB

    /// 发送文件：分解为 announce → 逐块发送 → complete
    /// callback: 每块通过回调传出（JSON 字节数组）
    fun sendFile(file: File, deviceID: String, onChunk: (ByteArray) -> Unit) {
        val fileName = file.name
        val fileSize = file.length()
        val totalChunks = ((fileSize + CHUNK_SIZE - 1) / CHUNK_SIZE).toInt()

        android.util.Log.i("FileTransfer", "Sending $fileName [$fileSize bytes, $totalChunks chunks]")

        // 1. Announce
        val announce = buildJSON(
            type = "fileAnnounce",
            deviceID = deviceID,
            fileName = fileName,
            fileSize = fileSize,
            totalChunks = totalChunks
        )
        onChunk(announce.toByteArray(Charsets.UTF_8))

        // 2. Chunks
        FileInputStream(file).use { input ->
            val buffer = ByteArray(CHUNK_SIZE)
            var chunkIndex = 0
            var bytesRead: Int
            while (input.read(buffer).also { bytesRead = it } > 0) {
                val chunkData = if (bytesRead < CHUNK_SIZE) buffer.copyOf(bytesRead) else buffer.copyOf()
                val base64 = android.util.Base64.encodeToString(chunkData, android.util.Base64.NO_WRAP)

                val chunk = buildJSON(
                    type = "fileChunk",
                    deviceID = deviceID,
                    fileName = fileName,
                    chunkIndex = chunkIndex,
                    totalChunks = totalChunks,
                    chunkData = base64
                )
                onChunk(chunk.toByteArray(Charsets.UTF_8))
                chunkIndex++
            }
        }

        // 3. Complete
        val complete = buildJSON(
            type = "fileComplete",
            deviceID = deviceID,
            fileName = fileName,
            fileSize = fileSize
        )
        onChunk(complete.toByteArray(Charsets.UTF_8))

        android.util.Log.i("FileTransfer", "Sent $fileName complete")
    }

    // ── Receive ──

    private val pendingFiles = mutableMapOf<String, PendingFile>()

    data class PendingFile(
        val fileName: String,
        val totalSize: Long,
        val totalChunks: Int,
        val startedAt: Long = System.currentTimeMillis(),
        val chunks: MutableMap<Int, ByteArray> = mutableMapOf()
    )

    /// 处理收到的文件块，返回 true 表示文件接收完毕
    fun receiveChunk(json: org.json.JSONObject, receiveDir: File): Boolean {
        val type = json.getString("type")
        val fileName = json.getString("fileName")

        return when (type) {
            "fileAnnounce" -> {
                val fileSize = json.getLong("fileSize")
                val totalChunks = json.getInt("totalChunks")
                synchronized(pendingFiles) {
                    pendingFiles[fileName] = PendingFile(fileName, fileSize, totalChunks)
                }
                android.util.Log.i("FileTransfer", "Receiving $fileName [$fileSize bytes]")
                false
            }
            "fileChunk" -> {
                val chunkIndex = json.getInt("chunkIndex")
                val totalChunks = json.getInt("totalChunks")
                val base64Data = json.getString("data")
                val chunkData = android.util.Base64.decode(base64Data, android.util.Base64.NO_WRAP)

                synchronized(pendingFiles) {
                    val pending = pendingFiles.getOrPut(fileName) {
                        PendingFile(fileName, 0, totalChunks)
                    }
                    pending.chunks[chunkIndex] = chunkData

                    if (pending.chunks.size == totalChunks) {
                        finalizeFile(pending, receiveDir)
                        pendingFiles.remove(fileName)
                        true
                    } else {
                        false
                    }
                }
            }
            "fileComplete" -> {
                // Force finalize whatever we have
                synchronized(pendingFiles) {
                    pendingFiles[fileName]?.let { finalizeFile(it, receiveDir) }
                    pendingFiles.remove(fileName)
                }
                true
            }
            else -> false
        }
    }

    private fun finalizeFile(pending: PendingFile, dir: File) {
        val outputFile = File(dir, pending.fileName)
        FileOutputStream(outputFile).use { out ->
            for (i in 0 until pending.totalChunks) {
                pending.chunks[i]?.let { out.write(it) }
            }
        }
        android.util.Log.i("FileTransfer", "Received ${pending.fileName} → ${outputFile.absolutePath}")
    }

    // ── JSON builder ──

    private fun buildJSON(
        type: String,
        deviceID: String,
        fileName: String? = null,
        fileSize: Long? = null,
        totalChunks: Int? = null,
        chunkIndex: Int? = null,
        chunkData: String? = null
    ): String {
        return org.json.JSONObject().apply {
            put("version", 1)
            put("deviceID", deviceID)
            put("timestamp", System.currentTimeMillis())
            put("type", type)
            fileName?.let { put("fileName", it) }
            fileSize?.let { put("fileSize", it) }
            totalChunks?.let { put("totalChunks", it) }
            chunkIndex?.let { put("chunkIndex", it) }
            chunkData?.let { put("data", it) }
        }.toString()
    }
}
