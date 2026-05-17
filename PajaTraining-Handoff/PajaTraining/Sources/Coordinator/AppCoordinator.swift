import Foundation
import GRDB

/// Central coordinator: user bootstrapping, exercise seeding, onboarding check.
final class AppCoordinator {
    private let db: DatabaseStore

    init(db: DatabaseStore) {
        self.db = db
    }

    // MARK: - User

    func ensureUser() async throws -> UserRecord {
        if let existing = try await db.read({ try UserRecord.fetchOne($0) }) {
            return existing
        }
        var user = UserRecord(
            id: UUID().uuidString,
            displayName: "Owner",
            timezone: TimeZone.current.identifier,
            createdAt: iso8601Now()
        )
        try await db.write { try user.insert($0) }
        return user
    }

    // MARK: - Exercise seeding

    func seedBuiltinExercises() async {
        let all = builtinExercises()
        _ = try? await db.write { db in
            for ex in all {
                let exists = try ExerciseRecord
                    .filter(Column("user_id") == nil)
                    .filter(Column("name") == ex.name)
                    .fetchCount(db) > 0
                if !exists {
                    var r = ex
                    try r.insert(db)
                }
            }
        }
    }

    private func builtinExercises() -> [ExerciseRecord] {
        let ppl = ProgramTemplates.ppl
        let ul  = ProgramTemplates.upperLower
        var seen = Set<String>()
        var out: [ExerciseRecord] = []
        for template in [ppl, ul] {
            for day in template.rotation {
                for slot in day.slots {
                    guard seen.insert(slot.name).inserted else { continue }
                    out.append(ExerciseRecord(
                        id: UUID().uuidString,
                        userId: nil,
                        name: slot.name,
                        category: slot.category.rawValue,
                        isMainLift: slot.isMainLift
                    ))
                }
            }
        }
        return out
    }

    // MARK: - Onboarding

    func isOnboarded(userId: String) async throws -> Bool {
        try await db.read { db in
            let hasProgram = try ProgramInstanceRecord
                .filter(Column("user_id") == userId)
                .filter(Column("status") == "active")
                .fetchCount(db) > 0
            let hasToken = KeychainStore.hasOuraToken()
            return hasProgram && hasToken
        }
    }

    // MARK: - Sync trigger

    func syncIfNeeded(userId: String) async {
        guard let token = try? KeychainStore.loadOuraToken() else { return }
        let store = GRDBDailyLogStore(db: db, userId: userId)
        let client = OuraClient(token: token, store: store)
        let resolver = ResolveCoordinator(db: db, userId: userId)
        let end = isoDate(Date())
        let start = isoDate(Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date())
        do {
            try await client.sync(from: start, to: end)
            for offset in 0..<14 {
                if let d = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) {
                    try? await resolver.rebuild(for: isoDate(d))
                }
            }
        } catch {
            // Sync failure is non-fatal — stale data shown with age
        }
    }
}

func iso8601Now() -> String { ISO8601DateFormatter().string(from: Date()) }
func isoDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f.string(from: date)
}
