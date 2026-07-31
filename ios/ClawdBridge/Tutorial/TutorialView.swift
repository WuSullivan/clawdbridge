import SwiftUI

struct TutorialView: View {
    @State private var currentPage = 0

    private let pages: [(title: String, icon: String, body: String)] = [
        (
            "🔄 零交互剪贴板同步",
            "doc.on.clipboard",
            "你复制，其他设备立即可用——不弹窗、不通知、纯后台。\n\n" +
            "Mac ↔ iOS 通过蓝牙直连，无需 Wi-Fi。" +
            "Mac ↔ Android 通过局域网 TCP。" +
            "只要设备在 2 米范围内，复制的内容自动同步。"
        ),
        (
            "📋 按需传输，省电优先",
            "bolt.horizontal",
            "不粘贴，不传输。\n\n" +
            "你复制内容后，ClawdBridge 只在其他设备粘贴时才真正传输数据。" +
            "平时只做极低功耗的蓝牙监听，几乎不耗电。\n\n" +
            "超过 3MB 的大文件会弹窗确认后再发送。"
        ),
        (
            "📱 保持后台运行",
            "gearshape.2",
            "要确保 ClawdBridge 在后台持续工作，请开启以下系统设置：\n\n" +
            "1. 打开「设置」→「通用」→「后台App刷新」\n" +
            "2. 确保 ClawdBridge 开关为开启状态\n" +
            "3. 不要从后台手动划掉 App\n\n" +
            "只要不删后台，它就会一直运行。SideStore 用户自动续签。"
        ),
        (
            "🤖 配对 Android 设备",
            "link",
            "1. 在 Android 设备上打开 ClawdBridge\n" +
            "2. 点击「配对新设备」→ 显示 6 位配对码\n" +
            "3. 在 Mac 端输入该配对码\n" +
            "4. 双方验证通过后建立加密连接\n\n" +
            "配对只需一次，后续自动连接。"
        ),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)

            Image(systemName: pages[currentPage].icon)
                .font(.system(size: 56))
                .foregroundColor(.accentColor)
                .padding(.bottom, 8)

            Text(pages[currentPage].title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            ScrollView {
                Text(pages[currentPage].body)
                    .font(.body)
                    .lineSpacing(6)
                    .padding(.horizontal, 32)
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Circle()
                        .fill(i == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            HStack(spacing: 16) {
                if currentPage > 0 {
                    Button("上一步") {
                        withAnimation { currentPage -= 1 }
                    }
                }

                if currentPage < pages.count - 1 {
                    Button("下一步") {
                        withAnimation { currentPage += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("✅ 开始使用") {
                        UserDefaults.standard.set(true, forKey: "tutorial_completed")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.bottom, 40)
        }
    }
}
