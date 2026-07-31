import Foundation
import BackgroundTasks

/// BGTaskScheduler 后台保活管理器
final class BGTaskManager {
    static let taskIdentifier = "com.clawdbridge.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        Logger.info("BGTaskScheduler: registered")
        schedule()
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            Logger.info("BGTaskScheduler: scheduled next run in ~15 min")
        } catch {
            Logger.error("BGTaskScheduler: schedule failed: \(error)")
        }
    }

    private static func handleAppRefresh(task: BGAppRefreshTask) {
        schedule()
        task.expirationHandler = {
            Logger.warn("BGTaskScheduler: task expired")
        }
        Logger.info("BGTaskScheduler: performing background check")
        BridgeSession.shared.monitor.performBackgroundCheck()
        task.setTaskCompleted(success: true)
    }
}
