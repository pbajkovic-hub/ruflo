import Foundation
import GRDB

@MainActor
final class TrendsViewModel: ObservableObject {
    struct RecoveryPoint: Identifiable {
        let id: String
        let date: String
        let pct: Int
        let state: RecoveryState
    }
    struct VolumePoint: Identifiable {
        let id = UUID().uuidString
        let weekStart: String
        let totalKg: Double
    }
    struct BodyCompPoint: Identifiable {
        let id: String
        let date: String
        let weightKg: Double?
        let bodyFatPct: Double?
    }

    @Published var recoveryPoints: [RecoveryPoint] = []
    @Published var volumePoints: [VolumePoint] = []
    @Published var bodyCompPoints: [BodyCompPoint] = []
    @Published var rangeDays: Int = 30
    @Published var isLoading = true

    private let db: DatabaseStore
    private let userId: String

    init(db: DatabaseStore, userId: String) {
        self.db = db
        self.userId = userId
    }

    func load() async {
        isLoading = true
        let cutoff = isoDate(Calendar.current.date(byAdding: .day,
                                                   value: -rangeDays, to: Date()) ?? Date())
        async let recovery = fetchRecovery(since: cutoff)
        async let volume = fetchVolume(since: cutoff)
        async let bodyComp = fetchBodyComp(since: cutoff)
        let (r, v, b) = await (recovery, volume, bodyComp)
        recoveryPoints = r
        volumePoints = v
        bodyCompPoints = b
        isLoading = false
    }

    private func fetchRecovery(since cutoff: String) async -> [RecoveryPoint] {
        (try? await db.read { db in
            try ResolvedDailyRecord
                .filter(Column("user_id") == self.userId)
                .filter(Column("log_date") >= cutoff)
                .filter(Column("recovery_pct") != nil)
                .order(Column("log_date"))
                .fetchAll(db)
                .compactMap { r -> RecoveryPoint? in
                    guard let pct = r.recoveryPct else { return nil }
                    let state = RecoveryState(rawValue: r.recoveryState ?? "") ?? .unknown
                    return RecoveryPoint(id: r.logDate, date: r.logDate, pct: pct, state: state)
                }
        }) ?? []
    }

    private func fetchVolume(since cutoff: String) async -> [VolumePoint] {
        (try? await db.read { db in
            try WeeklyLogRecord
                .filter(Column("user_id") == self.userId)
                .filter(Column("week_start_date") >= cutoff)
                .filter(Column("total_volume_kg") != nil)
                .order(Column("week_start_date"))
                .fetchAll(db)
                .compactMap { r -> VolumePoint? in
                    guard let vol = r.totalVolumeKg else { return nil }
                    return VolumePoint(weekStart: r.weekStartDate, totalKg: vol)
                }
        }) ?? []
    }

    private func fetchBodyComp(since cutoff: String) async -> [BodyCompPoint] {
        (try? await db.read { db in
            try BodyCompositionRecord
                .filter(Column("user_id") == self.userId)
                .filter(Column("measured_on") >= cutoff)
                .order(Column("measured_on"))
                .fetchAll(db)
                .map { r in
                    BodyCompPoint(id: r.id, date: r.measuredOn,
                                  weightKg: r.weightKg, bodyFatPct: r.bodyFatPct)
                }
        }) ?? []
    }
}
