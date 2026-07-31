package com.clawdbridge.network

import kotlinx.coroutines.*
import java.io.InputStream
import java.io.OutputStream
import java.net.Socket
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import java.security.SecureRandom

/// TCP 客户端：连接到 Mac（配对后）进行数据传输
/// + AES-256-GCM 加密
class CryptoSession(private val sharedKey: ByteArray) {
    companion object {
        private const val GCM_TAG_LENGTH = 128
        private const val GCM_IV_LENGTH = 12
        private const val ALGORITHM = "AES/GCM/NoPadding"

        fun deriveKey(pin: String): ByteArray {
            val salt = "clawdbridge-pin-salt-2026".toByteArray(Charsets.UTF_8)
            val spec = javax.crypto.spec.PBEKeySpec(
                pin.toCharArray(), salt, 100_000, 256
            )
            val factory = javax.crypto.SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            return factory.generateSecret(spec).encoded
        }
    }

    private val cipher: Cipher = Cipher.getInstance(ALGORITHM)

    fun encrypt(plaintext: ByteArray): ByteArray? {
        return try {
            val iv = ByteArray(GCM_IV_LENGTH).also { SecureRandom().nextBytes(it) }
            val keySpec = SecretKeySpec(sharedKey, "AES")
            val gcmSpec = GCMParameterSpec(GCM_TAG_LENGTH, iv)
            cipher.init(Cipher.ENCRYPT_MODE, keySpec, gcmSpec)
            val ciphertext = cipher.doFinal(plaintext)
            iv + ciphertext
        } catch (e: Exception) {
            android.util.Log.e("CryptoSession", "Encrypt failed", e)
            null
        }
    }

    fun decrypt(wrapped: ByteArray): ByteArray? {
        return try {
            val iv = wrapped.copyOfRange(0, GCM_IV_LENGTH)
            val encrypted = wrapped.copyOfRange(GCM_IV_LENGTH, wrapped.size)
            val keySpec = SecretKeySpec(sharedKey, "AES")
            val gcmSpec = GCMParameterSpec(GCM_TAG_LENGTH, iv)
            cipher.init(Cipher.DECRYPT_MODE, keySpec, gcmSpec)
            cipher.doFinal(encrypted)
        } catch (e: Exception) {
            android.util.Log.w("CryptoSession", "Decrypt failed (tag mismatch?)", e)
            null
        }
    }
}

/// TCP 连接管理器：连接 Mac，发送/接收加密载荷
class TCPClient(
    private val host: String,
    private val port: Int,
    private val crypto: CryptoSession
) {
    private var socket: Socket? = null
    private var inputStream: InputStream? = null
    private var outputStream: OutputStream? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    var onDisconnected: (() -> Unit)? = null
    var onPayloadReceived: ((ByteArray) -> Unit)? = null

    fun connect(): Boolean {
        return try {
            socket = Socket(host, port)
            inputStream = socket!!.getInputStream()
            outputStream = socket!!.getOutputStream()
            android.util.Log.i("TCPClient", "Connected to $host:$port")
            startReading()
            true
        } catch (e: Exception) {
            android.util.Log.e("TCPClient", "Connection failed: ${e.message}")
            false
        }
    }

    fun disconnect() {
        try { socket?.close() } catch (_: Exception) {}
        socket = null
        onDisconnected?.invoke()
    }

    /// 发送加密数据（4 字节长度前缀 + 加密载荷）
    fun send(payload: ByteArray): Boolean {
        val encrypted = crypto.encrypt(payload) ?: return false
        return try {
            val length = encrypted.size
            val header = ByteArray(4)
            header[0] = ((length shr 24) and 0xFF).toByte()
            header[1] = ((length shr 16) and 0xFF).toByte()
            header[2] = ((length shr 8) and 0xFF).toByte()
            header[3] = (length and 0xFF).toByte()

            outputStream?.write(header)
            outputStream?.write(encrypted)
            outputStream?.flush()
            true
        } catch (e: Exception) {
            android.util.Log.w("TCPClient", "Send failed: ${e.message}")
            false
        }
    }

    // ── 读取线程 ──

    private fun startReading() {
        scope.launch {
            try {
                val stream = inputStream ?: return@launch
                while (isActive && socket?.isConnected == true) {
                    // Read 4-byte length
                    val header = ByteArray(4)
                    var read = stream.read(header)
                    if (read < 4) break

                    val length = ((header[0].toInt() and 0xFF) shl 24) or
                            ((header[1].toInt() and 0xFF) shl 16) or
                            ((header[2].toInt() and 0xFF) shl 8) or
                            (header[3].toInt() and 0xFF)

                    if (length <= 0 || length > 100_000_000) {
                        android.util.Log.w("TCPClient", "Invalid message length: $length")
                        break
                    }

                    val payload = ByteArray(length)
                    var totalRead = 0
                    while (totalRead < length) {
                        read = stream.read(payload, totalRead, length - totalRead)
                        if (read < 0) break
                        totalRead += read
                    }

                    val decrypted = crypto.decrypt(payload)
                    if (decrypted != null) {
                        onPayloadReceived?.invoke(decrypted)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("TCPClient", "Read error: ${e.message}")
            } finally {
                disconnect()
            }
        }
    }
}

/// 本地 TCP 服务器：接受 Mac 连接
class TCPServer(
    private val port: Int,
    private val crypto: CryptoSession
) {
    private var serverSocket: java.net.ServerSocket? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    var onPayloadReceived: ((ByteArray) -> Unit)? = null

    fun start() {
        scope.launch {
            try {
                serverSocket = java.net.ServerSocket(port)
                android.util.Log.i("TCPServer", "Listening on port $port")

                while (isActive) {
                    val clientSocket = serverSocket?.accept() ?: break
                    android.util.Log.i("TCPServer", "Accepted connection from ${clientSocket.inetAddress}")

                    // Handle client in new coroutine
                    launch { handleConnection(clientSocket) }
                }
            } catch (e: Exception) {
                android.util.Log.e("TCPServer", "Server error: ${e.message}")
            }
        }
    }

    private suspend fun handleConnection(socket: Socket) = withContext(Dispatchers.IO) {
        try {
            val input = socket.getInputStream()
            while (isActive && socket.isConnected) {
                val header = ByteArray(4)
                if (input.read(header) < 4) break

                val length = ((header[0].toInt() and 0xFF) shl 24) or
                        ((header[1].toInt() and 0xFF) shl 16) or
                        ((header[2].toInt() and 0xFF) shl 8) or
                        (header[3].toInt() and 0xFF)

                val payload = ByteArray(length)
                var totalRead = 0
                while (totalRead < length) {
                    val r = input.read(payload, totalRead, length - totalRead)
                    if (r < 0) break
                    totalRead += r
                }

                val decrypted = crypto.decrypt(payload)
                if (decrypted != null) {
                    onPayloadReceived?.invoke(decrypted)
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("TCPServer", "Connection handler error: ${e.message}")
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }

    fun stop() {
        try { serverSocket?.close() } catch (_: Exception) {}
    }
}
