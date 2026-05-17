import Foundation
import GRDB

/// Rebuilds resolved_daily_metrics for one date from the raw daily_logs rows.
/// Called after every Oura upsert and Apple Health read.
struct ResolveCoordinator {
    private let db: DatabaseStore
    private let userId: String
    private let builder = ResolvedMetricsBuilder()

    init(db: DatabaseStore, userId: String) {
        self.db = db
        self.userId = userId
    }

    func rebuild(for date: String) async throws {
        // Gather raw daily_log rows for this date.
        let rawRows = try await db.read { database in
            try DailyLogRecord
                .filter(Column("user_id") == self.userId)
                .filter(Column("log_date") == date)
                .fetchAll(database)
        }
        let sources = rawRows.map { row in
            RawDay(source: row.source,
                   readinessScore: row.readinessScore,
                   sleepScore: row.sleepScore,
                   sleepTotalMin: row.sleepTotalMin,
                   hrvMs: row.hrvMs,
                   restingHr: row.restingHr,
                   workoutMin: row.workoutMin)
        }

        // Count prior basis days.
        let priorBasisDays = try await countPriorBasisDays(before: date)

        // Compute trailing baseline from last ~30 resolved days.
        let baseline = try await computeBaseline(before: date)

        let resolved = builder.resolve(date: date,
                                       sources: sources,
                                       baseline: baseline,
                                       priorBasisDays: priorBasisDays)

        // Persist (upsert by PK = user_id + log_date).
        try await db.write { database in
            var record = ResolvedDailyRecord(
                userId: self.userId,
                logDate: date,
                recoveryPct: resolved.recoveryPct,
                recoveryState: resolved.recoveryState.rawValue,
                confidence: resolved.confidence.rawValue,
                sleepScore: resolved.sleepScore,
                sleepTotalMin: resolved.sleepTotalMin,
                hrvMs: resolved.hrvMs,
                restingHr: resolved.restingHr,
                workoutMin: resolved.workoutMin,
                recoverySource: resolved.recoverySource,
                rebuiltAt: iso8601Now()
            )
            try record.save(database)
        }
    }

    private func countPriorBasisDays(before date: String) async throws -> Int {
        try await db.read { database in
            try Int.fetchOne(database, sql: """
                SELECT COUNT(DISTINCT log_date)
                FROM resolved_daily_metrics
                WHERE user_id = ? AND log_date < ? AND recovery_pct IS NOT NULL
            """, arguments: [self.userId, date]) ?? 0
        }
    }

    private func computeBaseline(before date: String) async throws -> Baseline? {
        let priorRecords = try await db.read { database in
            try ResolvedDailyRecord
                .filter(Column("user_id") == self.userId)
                .filter(Column("log_date") < date)
                .order(Column("log_date").desc)
                .limit(30)
                .fetchAll(database)
        }
        let days = priorRecords.map { r in
            ResolvedDaily(logDate: r.logDate,
                          recoveryPct: r.recoveryPct,
                          recoveryState: RecoveryState(rawValue: r.recoveryState ?? "") ?? .unknown,
                          confidence: RecoveryInput.Confidence(rawValue: r.confidence) ?? .none,
                          sleepScore: r.sleepScore,
                          sleepTotalMin: r.sleepTotalMin,
                          hrvMs: r.hrvMs,
                          restingHr: r.restingHr,
                          workoutMin: r.workoutMin,
                          recoverySource: r.recoverySource)
        }
        return builder.baseline(from: days)
    }
}

private func iso8601Now() -> String {
    ISO8601DateFormatter().string(from: Date())
}
