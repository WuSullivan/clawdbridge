# 🦞 ClawdBridge

**局域网零交互剪贴板 & 文件同步工具**

复制即同步。不弹窗，不通知，纯后台。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 为什么选择 ClawdBridge？

| | ClawdBridge | 苹果 Handoff | LocalSend |
|---|---|---|---|
| 复制即同步 | ✅ | ⚠️ 间歇断连 | ❌ 需手动选择 |
| 无弹窗 | ✅ | ✅ | ❌ |
| 跨平台 (Mac/Android) | ✅ | ❌ | ✅ |
| 蓝牙直连 (Mac↔iOS) | ✅ | ✅ | ❌ |
| 按需传输（省电） | ✅ | ❌ | ❌ |
| 开源 | ✅ | ❌ | ✅ |

## 核心特性

- **按需传输**：复制时不传输，粘贴时才拉取数据。平时极低功耗待机
- **蓝牙直连**：Mac ↔ iOS 通过 BLE 通信，无需 Wi-Fi
- **局域网直连**：Mac ↔ Android 通过 TCP，数据不经过公网
- **大文件确认**：超过 3MB 的文件弹窗确认后才传输
- **最新覆盖**：最新复制的内容始终覆盖旧的
- **自动信任**：同一 Apple ID 下设备自动配对
- **支持类型**：文字、图片、视频、文件

## 平台

| 平台 | 发现方式 | 连接方式 | 状态 |
|---|---|---|---|
| **macOS** | Bonjour + BLE + UDP | TCP / BLE | ✅ 通过编译 |
| **iOS** | BLE | CoreBluetooth | 🚧 |
| **Android** | UDP 广播 | TCP | 🚧 |

互通拓扑：
```
     iOS ←─ BLE ─→ Mac ←─ TCP ─→ Android
```

> iOS 通过 Mac 中继与 Android 通信。

## 快速开始

### macOS

```bash
git clone https://github.com/WuSullivan/clawdbridge.git
cd clawdbridge
./build.sh --mac

# 安装
sudo cp build/mac/clawdbridge /usr/local/bin/

# 开机自启（可选）
cp build/mac/clawdbridge.plist ~/Library/LaunchAgents/com.clawdbridge.daemon.plist
launchctl load ~/Library/LaunchAgents/com.clawdbridge.daemon.plist
```

### iOS

通过 **SideStore** 侧载 IPA：

```bash
./build.sh --ios    # 需要 Xcode
```

**后台保活设置**（重要）：

1. 打开「**设置** → 通用 → 后台 App 刷新」
2. 确保 ClawdBridge 开关为开启
3. **不要**从后台手动划掉 App

### Android

```bash
./build.sh --android
# APK: build/android/clawdbridge.apk
```

将 APK 传输到 Android 设备安装即可。

## 工作原理

```
用户复制文本 / 图片 / 文件
    │
    ▼
本机剪贴板监听器轮询检测 changeCount（每 0.5 秒）
    │
    ▼
打包为 ClipPayload（含 SHA256 去重 hash）
    │
    ▼
┌─── ≤3MB：直接广播到所有已信任设备
│
└───  >3MB：弹窗确认后广播
    │
    ▼
接收端写入剪贴板（覆盖旧内容）
    粘贴时真正使用数据
```

### 传输协议

| 路径 | 协议 | 端口/UUID |
|---|---|---|
| Mac ↔ iOS | BLE | 自定义 UUID |
| Mac ↔ Mac | Bonjour + TCP | 45455 |
| Mac ↔ Android | TCP（UDP 发现） | UDP 45454 / TCP 45455 |

## 隐私 & 安全

- ✅ 局域网 + 蓝牙直连，不经过互联网
- ✅ 零追踪、零遥测、零云端存储
- ✅ 开源 MIT 协议，代码可审计

## 项目结构

```
clawdbridge/
├── mac/               # macOS Swift SPM
├── ios/               # iOS SwiftUI + UIKit
├── android/           # Android Kotlin + Compose
├── proto/             # 通信协议文档
├── build.sh           # 一键构建
└── .github/workflows/ # CI/CD
```

## License

[MIT](LICENSE) © WuSullivan
