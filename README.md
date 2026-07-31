# ClawdBridge 🐾

> 复制即同步 · 零操作 · 全平台

Mac ↔ iPhone ↔ Android 剪贴板全自动同步。**不弹窗、不打断、不费电。**

## 核心理念

Apple Handoff 掉链子？ClawdBridge 替代它。

- **零点击**：复制完，对方直接粘贴。没有"发送"按钮、没有确认框
- **零弹窗**：没有任何传输提示、进度条、通知
- **极低占用**：Mac 端仅 **142KB**，空闲 CPU 0%，内存 < 10MB
- **局域网直连**：数据不出你的网络，不依赖任何服务器

## 平台支持

| 平台 | 状态 | 安装方式 |
|------|:----:|---------|
| macOS | ✅ Ready | 双击运行 / launchd 开机自启 |
| iOS | 🚧 开发中 | SideStore 侧载 |
| Android | 🚧 开发中 | APK 直装 |

## 配对方式

| | Mac ↔ iOS | Android ↔ 任意 |
|---|---|---|
| **方式** | iCloud 自动 | 6 位密码面对面 |
| **操作** | 零操作，同 Apple ID 即连通 | 一方生成码，另一方输入 |
| **协议** | Bonjour 自动发现 | UDP 广播配对 |

## 快速开始

### Mac

```bash
# 编译
git clone https://github.com/loongcabin/clawdbridge
cd clawdbridge
swift build -c release

# 运行
.build/arm64-apple-macosx/release/ClawdBridge

# 开机自启
.build/arm64-apple-macosx/release/ClawdBridge --install
```

### Android

下载最新 [APK](https://github.com/loongcabin/clawdbridge/releases)，安装后：
1. 看完教程（如何保活）
2. 生成 / 输入 6 位配对码
3. 完成。复制任何文字，对方直接粘贴

### iOS

1. 通过 SideStore 安装 IPA
2. 打开一次，看完教程
3. Mac 在同一 Wi-Fi 下自动发现
4. 后台会自动保活（BGTaskScheduler）

## 技术架构

```
┌─────────┐    HTTP :18763    ┌─────────┐    HTTP :18763    ┌──────────┐
│   Mac   │◄──────────────────►│  iPhone  │◄──────────────────►│ Android  │
│  Swift  │    Bonjour 发现    │  Swift   │    UDP 配对码     │  Kotlin  │
└─────────┘                    └─────────┘                    └──────────┘
     │                              │                              │
     └──────────────────────────────┴──────────────────────────────┘
                          同一局域网 · 直连 · 无服务器
```

## 协议

- 剪贴板文本：`POST /clip` → body = UTF-8 文本
- 文件传输：`POST /file` → body = 原始字节，header `X-Filename`
- 配对码：UDP `:18764`，发送 `PAIR <6位码>`，回复 `PAIR_OK`
- 服务发现：Bonjour `_clawdbridge._tcp`

## 限制

- 仅同一局域网可用（Wi-Fi / 热点均可）
- 初期仅文字，文件传输开发中
- iOS 需侧载（App Store 不允许此类后台行为）

## 开发

```bash
# Mac
swift build

# iOS
cd iOS && xcodegen generate && open ClawdBridge.xcodeproj

# Android
cd android && ./gradlew assembleDebug
```

## License

MIT — 自由使用，自由修改。
