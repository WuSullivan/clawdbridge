import SwiftUI

// MARK: - iOS 首次启动教程
// 只在初次打开时显示一次。教用户如何保活、如何配对。

struct TutorialView: View {
    @AppStorage("tutorialCompleted") private var completed = false
    
    var body: some View {
        if completed {
            HiddenView()
        } else {
            TutorialContent(onDone: { completed = true })
        }
    }
}

struct TutorialContent: View {
    let onDone: () -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "link.icloud")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        Text("ClawdBridge")
                            .font(.largeTitle).bold()
                        Text("复制即同步 · 零操作")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    
                    Divider()
                    
                    // Step 1
                    TutorialStep(
                        number: "1",
                        title: "如何让它不被杀？",
                        content: """
                        iOS 会主动杀后台 App。让 ClawdBridge 存活的方法：
                        
                        • 打开后下拉控制中心，确认它出现在「正在播放」区域
                        • 或者：设置 → 通用 → 后台App刷新 → 开启 ClawdBridge
                        • 切勿手动上滑杀掉（那等于卸载）
                        
                        ClawdBridge 使用 BLE 广播保持唤醒，功耗极低。
                        """
                    )
                    
                    // Step 2
                    TutorialStep(
                        number: "2",
                        title: "配对：自动 & 零配置",
                        content: """
                        只要你的 Mac 和 iPhone 登录同一个 iCloud 账户，
                        两端都运行 ClawdBridge 后，会自动发现并信任对方。
                        
                        无需手动输入 IP、无需扫码、无需确认。
                        局域网内自动连接。
                        """
                    )
                    
                    // Step 3
                    TutorialStep(
                        number: "3",
                        title: "使用：复制就是发送",
                        content: """
                        在 iPhone 上复制任何文字 → Mac 上直接粘贴。
                        在 Mac 上复制任何文字 → iPhone 上直接粘贴。
                        
                        支持文字 & 文件（大小不设限）。
                        没有任何弹窗、确认框、发送按钮。
                        """
                    )
                    
                    // Step 4
                    TutorialStep(
                        number: "4",
                        title: "怎么连 Android？",
                        content: """
                        ClawdBridge 支持跨平台！Android 端也装好后：
                        
                        • 一方点「生成配对码」→ 获得 6 位数字
                        • 另一方点「输入配对码」→ 输入这 6 位数字
                        • 双方同 Wi-Fi 下自动发现并连接
                        • Mac 端用相同协议互通
                        
                        苹果设备走 iCloud 自动配对，无需手动。
                        """
                    )
                    
                    // Step 5
                    TutorialStep(
                        number: "5",
                        title: "如果断了怎么办？",
                        content: """
                        1. 确认 Mac 和 iPhone 在同一 Wi-Fi 下
                        2. 重新打开 ClawdBridge（它会在后台重新连接）
                        3. macOS 端：终端运行 launchctl kickstart 恢复
                        
                        断线自动重连，最长 30 秒恢复。
                        """
                    )
                    
                    Spacer(minLength: 32)
                    
                    Button(action: onDone) {
                        Text("开始使用")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 24)
            }
            .navigationBarHidden(true)
        }
    }
}

struct TutorialStep: View {
    let number: String
    let title: String
    let content: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.title2).bold()
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(content)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Hidden View (invisible after tutorial)

struct HiddenView: View {
    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: 12) {
                Image(systemName: "checkmark.icloud")
                    .font(.largeTitle)
                    .foregroundColor(.green.opacity(0.6))
                Text("ClawdBridge 正在后台运行")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            // Start the engine
            // Engine is already started by AppDelegate
        }
    }
}

#Preview {
    TutorialView()
}
