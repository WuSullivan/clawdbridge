import Foundation
import BackgroundTasks

/// iOS 后台任务管理器
/// 注册 BGAppRefreshTask 维持 BLE Peripheral 在后台持续广播
/// 用户需在「设置→通用→后台App刷新」中开启 ClawdBridge
final class BGTaskManager {
    static let shared = BGTaskManager()
    static let taskID = "com.clawdbridge.refresh"

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { task in
            self.handleRefresh(task as! BGAppRefreshTask)
        }
        schedule()
        Logger.info("BGTaskManager: registered \(Self.taskID)")
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        do {
            try BGTaskScheduler.shared.submit(request)
            Logger.info("BGTaskManager: scheduled next refresh")
        } catch {
            Logger.error("BGTaskManager: schedule failed: \(error.localizedDescription)")
        }
    }

    private func handleRefresh(_ task: BGAppRefreshTask) {
        // 重新调度下一次
        schedule()

        // BLE 保活：重置 peripheral 状态
        SyncEngine.shared.start()

        task.setTaskCompleted(success: true)
        Logger.info("BGTaskManager: refresh completed")
    }
}
