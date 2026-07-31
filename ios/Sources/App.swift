import SwiftUI
import CoreBluetooth

@main
struct ClawdBridgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("tutorial_completed") private var tutorialCompleted = false

    var body: some Scene {
        WindowGroup {
            if tutorialCompleted {
                ContentView()
            } else {
                TutorialView()
            }
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("ClawdBridge 运行中")
                .font(.title2)
                .fontWeight(.bold)
            Text("蓝牙已开启，附近设备间自动同步剪贴板")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    var bleBridge: BLEBridge!

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 蓝牙桥
        bleBridge = BLEBridge()
        bleBridge.start()

        // 同步引擎
        SyncEngine.shared.setBLEBridge(bleBridge)
        SyncEngine.shared.start()

        // 后台任务注册
        BGTaskManager.shared.register()

        Logger.info("ClawdBridge(iOS): started, BLE advertising")
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // BLE Peripheral 在后台继续广播
        Logger.info("AppDelegate: entering background, BLE continues")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        Logger.info("AppDelegate: entering foreground")
    }
}
