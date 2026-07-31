package com.clawdbridge.sync

import android.util.Log
import java.io.File

/**
 * Android 文件传输：大文件按需拉取 / 本地中转
 * 配合 Mac 端 FileTransfer 使用
 */
class FileTransfer(private val cacheDir: File) {

    data class StagedFile(
        val hash: String,
        val payload: ClipPayload,
        val tempPath: File
    )

    private val staged = mutableMapOf<String, StagedFile>()

    fun stage(payload: ClipPayload): File? {
        val data = payload.data ?: return null
        val name = payload.fileName ?: "file_${payload.contentHash.take(8)}"
        val dest = File(cacheDir, "staged/$name")
        dest.parentFile?.mkdirs()
        try {
            dest.writeBytes(data)
            staged[payload.contentHash] = StagedFile(payload.contentHash, payload, dest)
            Log.i(TAG, "Staged: $name (${data.size} B)")
            return dest
        } catch (e: Exception) {
            Log.w(TAG, "Stage failed: ${e.message}")
            return null
        }
    }

    fun fetch(hash: String): ClipPayload? {
        val sf = staged[hash] ?: return null
        val data = sf.tempPath.readBytes()
        return sf.payload.copy(data = data)
    }

    fun cleanup(hash: String) {
        staged[hash]?.let { it.tempPath.delete() }
        staged.remove(hash)
    }

    fun cleanupTempDir() {
        val dir = File(cacheDir, "staged")
        if (dir.exists()) dir.deleteRecursively()
    }

    companion object {
        private const val TAG = "FileTransfer"
    }
}
