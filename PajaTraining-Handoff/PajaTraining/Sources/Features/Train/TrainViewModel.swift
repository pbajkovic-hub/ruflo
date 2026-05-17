import Foundation
import GRDB

@MainActor
final class TrainViewModel: ObservableObject {
    struct LoggedSet: Identifiable {
        let id: String
        var exerciseName: String
        var setNumber: Int
        var targetReps: Int
        var targetKg: Double
        var doneReps: Int
        var doneKg: Double
        var isBackoff: Bool
        var completed: Bool
    }

    @Published var loggedSets: [String: [LoggedSet]] = [:]  // exerciseName → sets
    @Published var activeSession: SessionRecord?
    @Published var isLoading = true
    @Published var sessionComplete = false

    private let db: DatabaseStore
    private let userId: String
    private var sessionId = ""
    private var prescribedSession: PrescribedSession?
    private var resolvedRecord: ResolvedDailyRecord?
    private var instanceId = ""

    init(db: DatabaseStore, userId: String) {
        self.db = db
        self.userId = userId
    }

    func load(prescribed: PrescribedSession?, resolved: ResolvedDailyRecord?) async {
        self.prescribedSession = prescribed
        self.resolvedRecord = resolved
        isLoading = true

        guard let prescribed else { isLoading = false; return }

        // Check for an existing in-progress session today.
        let today = isoDate(Date())
        if let existing = try? await db.read({ db in
            try SessionRecord
                .filter(Column("user_id") == self.userId)
                .filter(Column("session_date") == today)
                .filter(Column("status") == "in_progress")
                .filter(Column("deleted_at") == nil)
                .fetchOne(db)
        }) {
            sessionId = existing.id
            activeSession = existing
            await loadExistingSets()
        } else {
            await buildFromPrescription(prescribed)
        }
        isLoading = false
    }

    private func buildFromPrescription(_ p: PrescribedSession) async {
        let today = isoDate(Date())
        sessionId = UUID().uuidString
        instanceId = (try? await db.read { db in
            try ProgramInstanceRecord
                .filter(Column("user_id") == self.userId)
                .filter(Column("status") == "active")
                .fetchOne(db)?.id
        }) ?? ""

        var sets: [String: [LoggedSet]] = [:]
        for exercise in p.exercises {
            var exerciseSets: [LoggedSet] = []
            // Prefill from previous session for this exercise.
            let prior = await lastSessionSets(exerciseName: exercise.name)
            for (i, prescribed) in exercise.sets.enumerated() {
                let priorSet = prior.first(where: { $0.setNumber == prescribed.setNumber })
                exerciseSets.append(LoggedSet(
                    id: UUID().uuidString,
                    exerciseName: exercise.name,
                    setNumber: prescribed.setNumber,
                    targetReps: prescribed.reps,
                    targetKg: prescribed.kg,
                    doneReps: priorSet?.doneReps ?? prescribed.reps,
                    doneKg: priorSet?.doneKg ?? prescribed.kg,
                    isBackoff: prescribed.isBackoff,
                    completed: false
                ))
                _ = i
            }
            sets[exercise.name] = exerciseSets
        }
        loggedSets = sets
    }

    private func lastSessionSets(exerciseName: String) async -> [SetRecord] {
        (try? await db.read { db in
            let ex = try ExerciseRecord
                .filter(Column("name") == exerciseName)
                .fetchOne(db)
            guard let exId = ex?.id else { return [SetRecord]() }
            let sessionEx = try SessionExerciseRecord
                .filter(Column("exercise_id") == exId)
                .fetchAll(db)
            let latestId = sessionEx.last?.id
            guard let seId = latestId else { return [SetRecord]() }
            return try SetRecord
                .filter(Column("session_exercise_id") == seId)
                .order(Column("set_number"))
                .fetchAll(db)
        }) ?? []
    }

    private func loadExistingSets() async { /* load from DB for resume */ }

    func toggleSet(exerciseName: String, setId: String) {
        guard var sets = loggedSets[exerciseName],
              let idx = sets.firstIndex(where: { $0.id == setId }) else { return }
        sets[idx].completed.toggle()
        loggedSets[exerciseName] = sets
    }

    func adjustReps(exerciseName: String, setId: String, delta: Int) {
        guard var sets = loggedSets[exerciseName],
              let idx = sets.firstIndex(where: { $0.id == setId }) else { return }
        sets[idx].doneReps = max(0, sets[idx].doneReps + delta)
        loggedSets[exerciseName] = sets
    }

    func adjustKg(exerciseName: String, setId: String, delta: Double) {
        guard var sets = loggedSets[exerciseName],
              let idx = sets.firstIndex(where: { $0.id == setId }) else { return }
        sets[idx].doneKg = max(0, sets[idx].doneKg + delta)
        loggedSets[exerciseName] = sets
    }

    func finishSession() async throws {
        guard let prescribed = prescribedSession else { return }
        let today = isoDate(Date())
        let now = iso8601Now()
        let recovery = resolvedRecord

        try await db.write { db in
            // Save session record
            var session = SessionRecord(
                id: self.sessionId,
                userId: self.userId,
                programInstanceId: self.instanceId.isEmpty ? nil : self.instanceId,
                sessionDate: today,
                dayLabel: prescribed.dayLabel,
                status: "completed",
                recoveryState: prescribed.recoveryState.rawValue,
                recoveryPct: prescribed.recoveryPct,
                prescriptionWhy: prescribed.why,
                deletedAt: nil,
                createdAt: now
            )
            try session.save(db)

            // Save sets per exercise
            for exercise in prescribed.exercises {
                guard let sets = self.loggedSets[exercise.name] else { continue }
                let exRecord = try ExerciseRecord
                    .filter(Column("name") == exercise.name).fetchOne(db)
                guard let exId = exRecord?.id else { continue }
                var seRecord = SessionExerciseRecord(
                    id: UUID().uuidString,
                    sessionId: self.sessionId,
                    exerciseId: exId,
                    orderIndex: prescribed.exercises.firstIndex(where: { $0.name == exercise.name }) ?? 0
                )
                try seRecord.insert(db)
                for set in sets {
                    var setRec = SetRecord(
                        id: set.id,
                        sessionExerciseId: seRecord.id,
                        setNumber: set.setNumber,
                        targetReps: set.targetReps,
                        targetKg: set.targetKg,
                        doneReps: set.completed ? set.doneReps : nil,
                        doneKg: set.completed ? set.doneKg : nil,
                        rpe: nil,
                        isWarmup: false,
                        isBackoff: set.isBackoff,
                        completed: set.completed
                    )
                    try setRec.insert(db)
                }
            }
        }

        // Progress each main lift and advance rotation
        await applyProgression(prescribed: prescribed, recovery: recovery)
        await advanceRotation()
        sessionComplete = true
    }

    private func applyProgression(prescribed: PrescribedSession, recovery: ResolvedDailyRecord?) async {
        let wasGreen = prescribed.recoveryState == .green
        let highConf = (recovery?.confidence == "high")
        let engine = ProgressionEngine()

        for exercise in prescribed.exercises {
            guard let sets = loggedSets[exercise.name] else { continue }
            let completedCount = sets.filter { $0.completed }.count
            let totalCount = sets.count
            let allHit = completedCount == totalCount && totalCount > 0
            let outcome = allHit ? "hit" : (completedCount == 0 ? "missed" : "skipped")

            _ = try? await db.write { db in
                guard let ex = try ExerciseRecord.filter(Column("name") == exercise.name).fetchOne(db),
                      var prog = try LiftProgressRecord
                        .filter(Column("user_id") == self.userId)
                        .filter(Column("exercise_id") == ex.id)
                        .fetchOne(db)
                else { return }
                let current = WorkingSet(exerciseName: exercise.name,
                                        workingKg: prog.workingKg,
                                        targetReps: prog.targetReps)
                let next = engine.next(working: current,
                                       lastOutcome: outcome,
                                       wasGreen: wasGreen,
                                       highConfidence: highConf,
                                       isMainLift: exercise.isMainLift)
                prog.workingKg = next.workingKg
                prog.lastOutcome = outcome
                prog.updatedAt = iso8601Now()
                try prog.save(db)
            }
        }
    }

    private func advanceRotation() async {
        _ = try? await db.write { db in
            guard var inst = try ProgramInstanceRecord
                .filter(Column("user_id") == self.userId)
                .filter(Column("status") == "active")
                .fetchOne(db),
                  let prog = try ProgramRecord.fetchOne(db, key: inst.programId),
                  let template = ProgramTemplates.template(forKey: prog.templateKey)
            else { return }

            let oldIndex = inst.rotationIndex
            inst.rotationIndex = (oldIndex + 1) % template.rotation.count
            if inst.rotationIndex == 0 {
                inst.weekInBlock += 1
                if inst.weekInBlock % template.deloadEveryNWeeks == 0 {
                    // Deload week completed — reset counter next iteration
                }
                if inst.weekInBlock > template.deloadEveryNWeeks {
                    inst.weekInBlock = 1
                }
            }
            try inst.save(db)
        }
    }
}
