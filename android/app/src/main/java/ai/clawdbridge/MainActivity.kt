package ai.clawdbridge

import android.content.*
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.random.Random

class MainActivity : ComponentActivity() {

    private var service: ClipboardService? = null
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            service = (binder as ClipboardService.LocalBinder).getService()
        }
        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Start & bind service
        val intent = Intent(this, ClipboardService::class.java)
        startForegroundService(intent)
        bindService(intent, connection, Context.BIND_AUTO_CREATE)

        val prefs = getSharedPreferences("clawdbridge", MODE_PRIVATE)
        val tutorialCompleted = prefs.getBoolean("tutorial", false)

        setContent {
            MaterialTheme {
                if (!tutorialCompleted) {
                    TutorialScreen(onDone = {
                        prefs.edit().putBoolean("tutorial", true).apply()
                    })
                } else {
                    MainScreen(
                        service = service,
                        onAddPeer = { host -> service?.addPeer(host) },
                        onRemovePeer = { host -> service?.removePeer(host) }
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        unbindService(connection)
        super.onDestroy()
    }
}

// MARK: - Tutorial

@Composable
fun TutorialScreen(onDone: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Text("ClawdBridge", fontSize = 28.sp, fontWeight = FontWeight.Bold)
        Text("复制即同步 · 零操作", color = MaterialTheme.colorScheme.secondary)

        Divider()

        TutorialStep("1", "如何确保不被杀后台？",
            "• 打开后可划掉界面，但不要强行停止服务\n" +
            "• 设置 → 应用 → ClawdBridge → 电池 → 无限制\n" +
            "• 通知栏会显示「剪贴板同步中」以保持存活\n" +
            "• 开机自启（已自动配置）")

        TutorialStep("2", "配对：6 位密码面对面",
            "• 你和另一台设备在同一个 Wi-Fi 下\n" +
            "• 一方生成 6 位密码，另一方输入\n" +
            "• 配对后自动同步，无需再次操作\n" +
            "• Mac/iOS 同类产品也可互通（同协议）")

        TutorialStep("3", "使用：复制就是发送",
            "• 复制任何文字 → 对方直接粘贴\n" +
            "• 没有弹窗、没有确认框、没有发送按钮\n" +
            "• 支持文字（文件即将支持）\n" +
            "• 局域网直连，数据不出你的网络")

        Spacer(modifier = Modifier.weight(1f))

        Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) {
            Text("开始使用", modifier = Modifier.padding(vertical = 8.dp))
        }
    }
}

@Composable
fun TutorialStep(num: String, title: String, content: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Surface(
            shape = MaterialTheme.shapes.small,
            color = MaterialTheme.colorScheme.primaryContainer,
            modifier = Modifier.size(32.dp)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text(num, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onPrimaryContainer)
            }
        }
        Column {
            Text(title, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            Text(content, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
        }
    }
}

// MARK: - Main Screen

@Composable
fun MainScreen(
    service: ClipboardService?,
    onAddPeer: (String) -> Unit,
    onRemovePeer: (String) -> Unit
) {
    var showPairDialog by remember { mutableStateOf(false) }
    var showGenerateDialog by remember { mutableStateOf(false) }
    val peers = remember { mutableStateListOf<String>() }

    // Refresh peers
    LaunchedEffect(Unit) {
        while (true) {
            kotlinx.coroutines.delay(2000)
            peers.clear()
            service?.getPeers()?.let { peers.addAll(it) }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text("ClawdBridge", fontSize = 24.sp, fontWeight = FontWeight.Bold)
        Text("已连接设备", color = MaterialTheme.colorScheme.secondary, fontSize = 14.sp)

        if (peers.isEmpty()) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("暂无配对设备", fontWeight = FontWeight.Medium)
                    Text(
                        "点击下方按钮配对 Mac 或其他手机",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 14.sp
                    )
                }
            }
        }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(peers.toList()) { peer ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(peer, fontSize = 14.sp)
                        TextButton(onClick = { onRemovePeer(peer) }) {
                            Text("断开", color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(
                onClick = { showGenerateDialog = true },
                modifier = Modifier.weight(1f)
            ) {
                Text("生成配对码")
            }
            OutlinedButton(
                onClick = { showPairDialog = true },
                modifier = Modifier.weight(1f)
            ) {
                Text("输入配对码")
            }
        }
    }

    // Generate code dialog
    if (showGenerateDialog) {
        val code = remember {
            Random.nextInt(100000, 999999).toString()
        }
        AlertDialog(
            onDismissRequest = { showGenerateDialog = false },
            title = { Text("配对码") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("让对方在 App 中输入这 6 位数字：")
                    Text(code, fontSize = 32.sp, fontWeight = FontWeight.Bold)
                    Text(
                        "双方必须在同一 Wi-Fi 网络下",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 13.sp
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { showGenerateDialog = false }) {
                    Text("已告知对方")
                }
            }
        )
    }

    // Enter code dialog
    if (showPairDialog) {
        var input by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showPairDialog = false },
            title = { Text("输入配对码") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("输入对方设备显示的 6 位数字：")
                    OutlinedTextField(
                        value = input,
                        onValueChange = { if (it.length <= 6) input = it.filter { c -> c.isDigit() } },
                        visualTransformation = PasswordVisualTransformation(),
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (input.length == 6) {
                            // Derive peer IP from code + network scan
                            PairingEngine.scanAndPair(input) { host ->
                                onAddPeer(host)
                            }
                            showPairDialog = false
                        } else {
                            // Show error via Toast (outside Compose)
                        }
                    }
                ) {
                    Text("配对")
                }
            },
            dismissButton = {
                TextButton(onClick = { showPairDialog = false }) {
                    Text("取消")
                }
            }
        )
    }
}
