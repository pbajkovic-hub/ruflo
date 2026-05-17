import Foundation
import GRDB

/// GRDB-backed implementation of the DailyLogStore protocol (defined in OuraClient.swift).
/// Called synchronously from within OuraClient.sync (which is already async).
final class GRDBDailyLogStore: DailyLogStore {
    private let db: DatabaseStore
    private let userId: String

    init(db: DatabaseStore, userId: String) {
        self.db = db
        self.userId = userId
    }

    func existingOura(date: String) throws -> (recordId: String?, updatedAt: String?)? {
        try db.syncRead { database in
            try DailyLogRecord
                .filter(Column("user_id") == self.userId)
                .filter(Column("log_date") == date)
                .filter(Column("source") == "oura")
                .fetchOne(database)
                .map { ($0.sourceRecordId, $0.sourceUpdatedAt) }
        }
    }

    func upsertOura(_ log: OuraDailyLog) throws {
        try db.syncWrite { db in
            // Fetch existing row id so we can update in-place.
            let existing = try DailyLogRecord
                .filter(Column("user_id") == self.userId)
                .filter(Column("log_date") == log.logDate)
                .filter(Column("source") == "oura")
                .fetchOne(db)

            var record = DailyLogRecord(
                id: existing?.id ?? UUID().uuidString,
                userId: self.userId,
                logDate: log.logDate,
                source: "oura",
                sourceRecordId: log.sourceRecordId,
                sourceUpdatedAt: log.sourceUpdatedAt,
                readinessScore: log.readinessScore,
                sleepScore: log.sleepScore,
                sleepTotalMin: log.sleepTotalMin,
                hrvMs: log.hrvMs,
                restingHr: log.restingHr,
                tempDeviation: log.tempDeviation,
                steps: log.steps,
                activeKcal: log.activeKcal,
                workoutMin: log.workoutMin,
                rawPayload: log.rawPayload,
                syncedAt: iso8601Now()
            )
            try record.save(db)
        }
    }

    // MARK: Apple Health upsert (not part of DailyLogStore protocol — called directly)

    func upsertAppleHealth(_ log: AppleHealthDailyLog) async throws {
        try await db.write { db in
            let existing = try DailyLogRecord
                .filter(Column("user_id") == self.userId)
                .filter(Column("log_date") == log.logDate)
                .filter(Column("source") == "apple_health")
                .fetchOne(db)

            var record = DailyLogRecord(
                id: existing?.id ?? UUID().uuidString,
                userId: self.userId,
                logDate: log.logDate,
                source: "apple_health",
                sourceRecordId: nil,
                sourceUpdatedAt: nil,
                readinessScore: nil,
                sleepScore: nil,
                sleepTotalMin: log.sleepTotalMin,
                hrvMs: log.hrvMs,
                restingHr: log.restingHr,
                tempDeviation: nil,
                steps: log.steps,
                activeKcal: log.activeKcal,
                workoutMin: log.workoutMin,
                rawPayload: log.rawPayload,
                syncedAt: iso8601Now()
            )
            try record.save(db)
        }
    }

    func upsertBodyComposition(_ bc: AppleHealthBodyComposition) async throws {
        try await db.write { db in
            let existing = try BodyCompositionRecord
                .filter(Column("user_id") == self.userId)
                .filter(Column("measured_on") == bc.measuredOn)
                .filter(Column("source") == "apple_health")
                .fetchOne(db)

            var record = BodyCompositionRecord(
                id: existing?.id ?? UUID().uuidString,
                userId: self.userId,
                measuredOn: bc.measuredOn,
                source: "apple_health",
                weightKg: bc.weightKg,
                bodyFatPct: bc.bodyFatPct,
                skeletalMuscleMassKg: nil,
                leanBodyMassKg: bc.leanBodyMassKg,
                totalBodyWaterL: nil,
                visceralFatLevel: nil,
                bmrKcal: nil,
                bmi: bc.bmi,
                inbodyScore: nil,
                segmentalLeanJson: nil,
                rawPayload: nil,
                notes: nil,
                createdAt: iso8601Now()
            )
            try record.save(db)
        }
    }
}

private func iso8601Now() -> String {
    ISO8601DateFormatter().string(from: Date())
}
