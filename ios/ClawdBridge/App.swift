import SwiftUI

/// iOS App 入口：无 UI 的纯后台 App
/// - 首次启动 → 显示教程页
/// - 后续启动 → 静默启动后台同步
@main
struct ClawdBridgeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.showTutorial {
                TutorialView()
                    .onDisappear {
                        appState.showTutorial = false
                        UserDefaults.standard.set(true, forKey: "tutorial_completed")
                    }
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
                    .onAppear {
                        appState.startBridge()
                    }
            }
        }
    }
}

/// App 状态管理
class AppState: ObservableObject {
    @Published var showTutorial: Bool

    init() {
        showTutorial = !UserDefaults.standard.bool(forKey: "tutorial_completed")
        if !showTutorial {
            startBridge()
        }
    }

    func startBridge() {
        guard UserDefaults.standard.bool(forKey: "tutorial_completed") else { return }
        Logger.info("iOS: starting bridge session")
    }
}
