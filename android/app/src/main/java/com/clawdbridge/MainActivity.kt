package com.clawdbridge

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clawdbridge.pairing.PairingActivity
import com.clawdbridge.service.BridgeService
import com.clawdbridge.tutorial.TutorialActivity

/// 主 Activity：轻量根入口
/// - 首次启动 → 打开 TutorialActivity（一次性教程）
/// - 后续启动 → 不显示 UI，直接启动后台服务
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val prefs = androidx.preference.PreferenceManager.getDefaultSharedPreferences(this)
        val tutorialCompleted = prefs.getBoolean("tutorial_completed", false)

        if (!tutorialCompleted) {
            // First launch: show tutorial
            startActivity(Intent(this, TutorialActivity::class.java))
        }

        // Always start the bridge service
        startBridgeService()

        // Show minimal UI (status overview)
        setContent {
            MaterialTheme {
                MainScreen(onPairClick = {
                    startActivity(Intent(this, PairingActivity::class.java))
                })
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // If brought to foreground, just show status — no extra UI
    }

    private fun startBridgeService() {
        val intent = Intent(this, BridgeService::class.java)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}

@Composable
fun MainScreen(onPairClick: () -> Unit) {
    var isRunning by remember { mutableStateOf(true) }

    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)
        ) {
            Text(
                text = "ClawdBridge",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold
            )

            Text(
                text = if (isRunning) "🟢 剪贴板同步运行中" else "🔴 服务未启动",
                fontSize = 18.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(32.dp))

            Text(
                text = "复制即同步 · 零操作 · 纯后台",
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(16.dp))

            Button(onClick = onPairClick) {
                Text("⚙ 配对新设备")
            }

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "配对后自动连接，无需重复操作",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.outline
            )
        }
    }
}
