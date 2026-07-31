package com.clawdbridge.pairing

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch

/// 配对 Activity：支持两种模式
/// 模式 A: 显示 PIN → 用户在 Mac 端输入（当 Mac 发起配对时，Android 显示 PIN 等 Mac 确认）
/// 模式 B: 输入 PIN → 用户手动输入（当 Android 发现未配对的 Mac 时，输入 Mac 端显示的 PIN）
class PairingActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            MaterialTheme {
                PairingScreen()
            }
        }
    }
}

@Composable
fun PairingScreen() {
    var mode by remember { mutableStateOf("input") } // "input" or "display"
    var pin by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var isError by remember { mutableStateOf(false) }

    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically)
        ) {
            Text(
                text = "🔑 配对新设备",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold
            )

            Text(
                text = "请确保两台设备在同一 Wi-Fi 网络下",
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Divider()

            // Mode toggle
            Row(
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                FilterChip(
                    selected = mode == "input",
                    onClick = { mode = "input" },
                    label = { Text("输入配对码") }
                )
                FilterChip(
                    selected = mode == "display",
                    onClick = { mode = "display" },
                    label = { Text("显示配对码") }
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            if (mode == "input") {
                // PIN Input Mode
                Text(
                    text = "请输入 Mac 端显示的 6 位配对码",
                    fontSize = 16.sp
                )

                OutlinedTextField(
                    value = pin,
                    onValueChange = {
                        if (it.length <= 6 && it.all { c -> c.isDigit() }) {
                            pin = it
                        }
                    },
                    label = { Text("配对码") },
                    placeholder = { Text("000000") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                    isError = isError
                )

                if (status.isNotEmpty()) {
                    Text(
                        text = status,
                        color = if (isError) MaterialTheme.colorScheme.error
                                else MaterialTheme.colorScheme.primary,
                        fontSize = 14.sp,
                        textAlign = TextAlign.Center
                    )
                }

                Button(
                    onClick = {
                        if (pin.length == 6) {
                            // Send PIN verification via UDP
                            status = "验证中..."
                            isError = false
                        } else {
                            status = "请输入完整的 6 位配对码"
                            isError = true
                        }
                    },
                    enabled = pin.length == 6,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("✅ 验证配对")
                }
            } else {
                // PIN Display Mode
                val generatedPin = remember {
                    String.format("%06d", (Math.random() * 1000000).toInt())
                }

                Text(
                    text = "请在另一台设备上输入此配对码：",
                    fontSize = 16.sp
                )

                Text(
                    text = generatedPin,
                    fontSize = 48.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 10.sp,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.fillMaxWidth()
                )

                Text(
                    text = "配对码 5 分钟内有效",
                    fontSize = 14.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "💡 提示：配对只需一次，后续自动连接",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.outline,
                textAlign = TextAlign.Center
            )
        }
    }
}
