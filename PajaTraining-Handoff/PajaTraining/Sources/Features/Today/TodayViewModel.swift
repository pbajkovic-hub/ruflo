import Foundation
import GRDB

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var session: PrescribedSession?
    @Published var resolved: ResolvedDailyRecord?
    @Published var isLoading = true
    @Published var priorBasisDays = 0

    private let db: DatabaseStore
    private let userId: String
    let today: String

    init(db: DatabaseStore, userId: String) {
        self.db = db
        self.userId = userId
        self.today = isoDate(Date())
    }

    func load() async {
        isLoading = true
        do {
            resolved = try await db.read { db in
                try ResolvedDailyRecord
                    .filter(Column("user_id") == self.userId)
                    .filter(Column("log_date") == self.today)
                    .fetchOne(db)
            }
            priorBasisDays = try await db.read { db in
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(DISTINCT log_date) FROM resolved_daily_metrics
                    WHERE user_id = ? AND log_date < ? AND recovery_pct IS NOT NULL
                """, arguments: [self.userId, self.today]) ?? 0
            }
            let (instance, template) = try await activeProgram()
            guard let instance, let template else {
                isLoading = false; return
            }
            let templateDay = template.rotation[instance.rotationIndex % template.rotation.count]
            let workingTable = try await buildWorkingTable(day: templateDay)
            let isDeload = (instance.weekInBlock % template.deloadEveryNWeeks == 0)
            let recovery = buildRecoveryInput()
            session = AdaptiveEngine().prescribe(day: templateDay,
                                                 recovery: recovery,
                                                 working: workingTable,
                                                 isDeloadWeek: isDeload)
        } catch { /* show empty state */ }
        isLoading = false
    }

    private func activeProgram() async throws -> (ProgramInstanceRecord?, ProgramTemplate?) {
        let instance = try await db.read { db in
            try ProgramInstanceRecord
                .filter(Column("user_id") == self.userId)
                .filter(Column("status") == "active")
                .fetchOne(db)
        }
        guard let instance else { return (nil, nil) }
        let prog = try await db.read { db in
            try ProgramRecord.fetchOne(db, key: instance.programId)
        }
        guard let prog else { return (nil, nil) }
        return (instance, ProgramTemplates.template(forKey: prog.templateKey))
    }

    private func buildWorkingTable(day: TemplateDay) async throws -> [String: WorkingSet] {
        let names = day.slots.map { $0.name }
        let rows = try await db.read { db in
            try LiftProgressRecord
                .filter(Column("user_id") == self.userId)
                .fetchAll(db)
        }
        let exercises = try await db.read { db in
            try ExerciseRecord
                .filter(Column("user_id") == nil)
                .fetchAll(db)
        }
        let exById = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        var table: [String: WorkingSet] = [:]
        for row in rows {
            guard let ex = exById[row.exerciseId], names.contains(ex.name) else { continue }
            table[ex.name] = WorkingSet(exerciseName: ex.name,
                                        workingKg: row.workingKg,
                                        targetReps: row.targetReps)
        }
        return table
    }

    func buildRecoveryInput() -> RecoveryInput {
        guard let r = resolved else {
            return RecoveryInput(state: .unknown, pct: nil, confidence: .none)
        }
        let state = RecoveryState(rawValue: r.recoveryState ?? "") ?? .unknown
        let conf = RecoveryInput.Confidence(rawValue: r.confidence) ?? .none
        return RecoveryInput(state: state, pct: r.recoveryPct, confidence: conf)
    }
}
