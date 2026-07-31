package ai.clawdbridge

import android.app.*
import android.content.*
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.io.*
import java.net.*

/**
 * Foreground service: clipboard watcher + HTTP sender.
 * Keeps a persistent notification so Android doesn't kill it.
 */
class ClipboardService : Service() {

    private var lastClip: String? = null
    private var peers = mutableSetOf<String>() // "host:port"
    private val port = 18763

    inner class LocalBinder : Binder() {
        fun getService(): ClipboardService = this@ClipboardService
    }

    override fun onBind(intent: Intent?): IBinder = LocalBinder()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(1, buildNotification())
        loadPeers()
        startClipboardWatcher()
        startHttpServer()
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        val channelId = "clawdbridge"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, "ClawdBridge Sync",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Clipboard sync active"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("ClawdBridge")
            .setContentText("剪贴板同步中…")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    // --- Clipboard Watcher ---
    private fun startClipboardWatcher() {
        Thread {
            val clipboard = getSystemService(ClipboardManager::class.java)
            while (true) {
                try {
                    val clip = clipboard?.primaryClip
                    if (clip != null && clip.itemCount > 0) {
                        val text = clip.getItemAt(0).text?.toString() ?: ""
                        if (text.isNotEmpty() && text != lastClip) {
                            lastClip = text
                            pushToPeers(text)
                        }
                    }
                    Thread.sleep(500)
                } catch (_: Exception) {}
            }
        }.start()
    }

    // --- HTTP Server (receive from peers) ---
    private fun startHttpServer() {
        Thread {
            try {
                val server = ServerSocket(port)
                while (true) {
                    val client = server.accept()
                    Thread { handleClient(client) }.start()
                }
            } catch (_: Exception) {}
        }.start()
    }

    private fun handleClient(client: Socket) {
        try {
            val reader = BufferedReader(InputStreamReader(client.getInputStream()))
            val firstLine = reader.readLine() ?: return
            val parts = firstLine.split(" ")
            if (parts.size < 2) return

            var contentLen = 0
            while (true) {
                val header = reader.readLine()
                if (header.isNullOrBlank()) break
                if (header.lowercase().startsWith("content-length:")) {
                    contentLen = header.substringAfter(":").trim().toIntOrNull() ?: 0
                }
            }

            if (parts[0] == "POST" && parts[1] == "/clip") {
                val body = CharArray(contentLen)
                reader.read(body, 0, contentLen)
                val text = String(body)
                writeClipboard(text)
                respond(client, 200, "OK")
            } else {
                respond(client, 404, "Not Found")
            }
        } catch (_: Exception) {
        } finally {
            client.close()
        }
    }

    private fun writeClipboard(text: String) {
        lastClip = text
        val clipboard = getSystemService(ClipboardManager::class.java)
        val clip = ClipData.newPlainText("clawdbridge", text)
        clipboard?.setPrimaryClip(clip)
    }

    private fun respond(client: Socket, status: Int, body: String) {
        val response = """
            HTTP/1.1 $status ${if (status == 200) "OK" else "Error"}
            Content-Type: text/plain
            Content-Length: ${body.length}
            Connection: close

            $body
        """.trimIndent()
        client.getOutputStream().write(response.toByteArray())
    }

    // --- Push to Peers ---
    private fun pushToPeers(text: String) {
        for (peer in peers) {
            try {
                val parts = peer.split(":")
                val host = parts[0]
                val p = if (parts.size > 1) parts[1].toInt() else port
                val url = URL("http://$host:$p/clip")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "text/plain")
                conn.connectTimeout = 3000
                conn.readTimeout = 3000
                conn.outputStream.write(text.toByteArray())
                conn.responseCode // trigger
                conn.disconnect()
            } catch (_: Exception) {
                // peer offline — skip
            }
        }
    }

    // --- Peer Management ---
    fun addPeer(host: String) {
        val addr = if (host.contains(":")) host else "$host:$port"
        peers.add(addr)
        savePeers()
    }

    fun removePeer(host: String) {
        peers.remove(host)
        savePeers()
    }

    fun getPeers(): Set<String> = peers.toSet()

    private fun loadPeers() {
        val prefs = getSharedPreferences("clawdbridge", MODE_PRIVATE)
        val saved = prefs.getStringSet("peers", emptySet()) ?: emptySet()
        peers = saved.toMutableSet()
    }

    private fun savePeers() {
        val prefs = getSharedPreferences("clawdbridge", MODE_PRIVATE)
        prefs.edit().putStringSet("peers", peers).apply()
    }

    override fun onDestroy() {
        super.onDestroy()
        // Restart if killed
        val intent = Intent(this, ClipboardService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
