package ai.clawdbridge

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import kotlin.concurrent.thread

/**
 * 6-digit PIN pairing over LAN via UDP broadcast.
 *
 * Flow:
 *   Device A: generates code "123456" → advertises via UDP broadcast
 *   Device B: user enters "123456" → broadcasts "PAIR 123456"
 *   Device A: receives "PAIR 123456" → responds with "PAIR_OK"
 *   Device B: receives response → saves peer IP
 *
 * Same Wi-Fi only. No internet. No server.
 */
object PairingEngine {

    private const val PAIR_PORT = 18764

    fun startAdvertiser(code: String, onPaired: (String) -> Unit) {
        thread {
            try {
                val socket = DatagramSocket(null)
                socket.reuseAddress = true
                socket.broadcast = true
                socket.bind(InetSocketAddress(PAIR_PORT))
                socket.soTimeout = 120_000 // 2 minutes

                val buf = ByteArray(64)
                while (true) {
                    val packet = DatagramPacket(buf, buf.size)
                    try {
                        socket.receive(packet)
                        val msg = String(packet.data, 0, packet.length)
                        if (msg == "PAIR $code") {
                            // Respond & save peer
                            val peerAddr = packet.address.hostAddress ?: continue
                            val resp = "PAIR_OK".toByteArray()
                            socket.send(DatagramPacket(resp, resp.size, packet.address, PAIR_PORT))
                            onPaired(peerAddr)
                        }
                    } catch (_: Exception) {
                        // timeout, stop advertising
                        socket.close()
                        return@thread
                    }
                }
            } catch (_: Exception) {
                // socket error
            }
        }
    }

    /**
     * Called on the device that enters the code.
     * Broadcasts PAIR <code>, waits for PAIR_OK response.
     */
    fun scanAndPair(code: String, onPaired: (String) -> Unit) {
        thread {
            try {
                val socket = DatagramSocket()
                socket.broadcast = true
                socket.soTimeout = 5000

                val msg = "PAIR $code"
                val data = msg.toByteArray()
                val broadcast = InetAddress.getByName("255.255.255.255")
                socket.send(DatagramPacket(data, data.size, broadcast, PAIR_PORT))

                // Wait for response
                val buf = ByteArray(64)
                val packet = DatagramPacket(buf, buf.size)
                try {
                    socket.receive(packet)
                    val resp = String(packet.data, 0, packet.length)
                    if (resp == "PAIR_OK") {
                        val peerAddr = packet.address.hostAddress ?: return@thread
                        onPaired(peerAddr)
                    }
                } catch (_: Exception) {
                    // No response
                }
                socket.close()
            } catch (_: Exception) {
                // Network error
            }
        }
    }
}
