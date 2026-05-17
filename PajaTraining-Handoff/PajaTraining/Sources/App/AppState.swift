import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isBootstrapping = true
    @Published var needsOnboarding = false
    @Published var userId: String = ""

    let db: DatabaseStore
    let coordinator: AppCoordinator

    init() {
        let store = DatabaseStore()
        self.db = store
        self.coordinator = AppCoordinator(db: store)
    }

    func bootstrap() async {
        isBootstrapping = true
        do {
            try await db.setup()
            let user = try await coordinator.ensureUser()
            userId = user.id
            await coordinator.seedBuiltinExercises()
            let onboarded = try await coordinator.isOnboarded(userId: user.id)
            needsOnboarding = !onboarded
            if onboarded {
                Task { await coordinator.syncIfNeeded(userId: user.id) }
            }
        } catch {
            needsOnboarding = true
        }
        isBootstrapping = false
    }

    func completeOnboarding() async {
        guard let user = try? await coordinator.ensureUser() else { return }
        userId = user.id
        await coordinator.syncIfNeeded(userId: user.id)
        needsOnboarding = false
    }
}
