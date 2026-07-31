package com.clawdbridge.tutorial

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clawdbridge.MainActivity

/// 首次启动教程页面：只显示一次，完成后关闭
class TutorialActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            MaterialTheme {
                TutorialScreen(onComplete = {
                    val prefs = androidx.preference.PreferenceManager.getDefaultSharedPreferences(this)
                    prefs.edit().putBoolean("tutorial_completed", true).apply()

                    // Return to main (which will auto-start service)
                    startActivity(Intent(this, MainActivity::class.java))
                    finish()
                })
            }
        }
    }
}

@Composable
fun TutorialScreen(onComplete: () -> Unit) {
    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically)
        ) {
            Text(
                text = "🔄 ClawdBridge",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold
            )

            Text(
                text = "局域网零交互剪贴板同步",
                fontSize = 16.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Divider()

            // Section 1
            TutorialSection(
                title = "1️⃣ 这是什么？",
                body = "ClawdBridge 让你在同一 Wi-Fi 下的设备间共享剪贴板和文件。" +
                        "只需复制，其他设备即刻可用——完全静默，无弹窗、无通知。"
            )

            // Section 2
            TutorialSection(
                title = "2️⃣ 如何配对？",
                body = "• Mac ↔ Android：打开本 App 的配对新设备 → 输入 Mac 上显示的 6 位 PIN → 完成\n" +
                        "• Mac ↔ iOS：同一 Apple ID 下自动信任，无需任何操作\n" +
                        "• iOS ↔ Android：通过 Mac 中继，双方都已配对 Mac 即可互通"
            )

            // Section 3
            TutorialSection(
                title = "3️⃣ 后台保活说明",
                body = "Android 使用前台服务保持后台运行。你会在通知栏看到"ClawdBridge 服务运行中"的提示。" +
                        "这是 Android 系统要求的前台服务通知，无法隐藏，但不打扰正常使用。\n\n" +
                        "建议在系统设置 → 电池 → 应用中关闭 ClawdBridge 的电池优化限制，以确保长时间稳定运行。"
            )

            // Section 4
            TutorialSection(
                title = "4️⃣ 隐私与安全",
                body = "• 所有通信仅限局域网，不经公网服务器\n" +
                        "• 传输内容使用 AES-256-GCM 加密\n" +
                        "• 无跟踪、无分析、无云端存储\n" +
                        "• 开源透明，代码可审计"
            )

            Spacer(modifier = Modifier.height(16.dp))

            Button(
                onClick = onComplete,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("✅ 开始使用", fontSize = 18.sp)
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

@Composable
fun TutorialSection(title: String, body: String) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = title,
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = body,
            fontSize = 14.sp,
            lineHeight = 22.sp,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}
