import Foundation
import BackgroundTasks

/// Registers and handles the Oura background refresh task.
/// Call `OuraSyncService.register()` once at app launch.
struct OuraSyncService {
    static let taskIdentifier = "com.paja.pajatraining.oura-sync"

    static func register(db: DatabaseStore, userId: String) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handle(task: task as! BGAppRefreshTask, db: db, userId: userId)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 60 * 60) // 3 hours
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(task: BGAppRefreshTask, db: DatabaseStore, userId: String) {
        schedule() // reschedule for next time
        let coordinator = AppCoordinator(db: db)
        let syncTask = Task {
            await coordinator.syncIfNeeded(userId: userId)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            syncTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
