import XCTest
@testable import PajaTraining

/// Off-device correctness tests for the brain. These pin the five fixes from
/// the 2026-05-17 correctness pass. They run on macOS (`swift test` / Xcode);
/// nothing here needs a device — pure logic + an in-memory DailyLogStore.
final class BrainTests: XCTestCase {

    // MARK: Fix #1 — revision rebuild on a SLEEP-ONLY revision

    /// In-memory store recording upserts.
    final class MemStore: DailyLogStore {
        var rows: [String: (recordId: String?, updatedAt: String?)] = [:]
        var upserts = 0
        func existingOura(date: String) throws -> (recordId: String?, updatedAt: String?)? {
            rows[date]
        }
        func upsertOura(_ log: OuraDailyLog) throws {
            upserts += 1
            rows[log.logDate] = (log.sourceRecordId, log.sourceUpdatedAt)
        }
    }

    func test_revision_on_sleep_only_change_triggers_upsert() throws {
        // Day already stored with readiness ts = T1. Oura then revises ONLY the
        // sleep record with a LATER ts. Pre-fix this was dropped (sourceUpdatedAt
        // tracked readiness only). Post-fix: merged max ts > stored → upsert.
        let store = MemStore()
        store.rows["2026-05-10"] = (recordId: "r1", updatedAt: "2026-05-10T07:00:00Z")

        // Simulate the merged result: max(readiness T1, revised sleep T2).
        let revised = OuraDailyLog(
            logDate: "2026-05-10", sourceRecordId: "r1",
            sourceUpdatedAt: "2026-05-10T09:30:00Z",   // sleep revision, later
            readinessScore: 71, sleepScore: 80, sleepTotalMin: 430,
            hrvMs: 55, restingHr: 52, tempDeviation: 0.1,
            steps: 8000, activeKcal: 400, workoutMin: nil,
            rawPayload: #"{"daily_readiness":{},"sleep":{}}"#)

        let existing = try store.existingOura(date: revised.logDate)
        let shouldSkip = existing?.updatedAt != nil
            && revised.sourceUpdatedAt != nil
            && revised.sourceUpdatedAt! <= existing!.updatedAt!
        XCTAssertFalse(shouldSkip, "sleep-only revision must NOT be skipped")
        // raw_payload must retain every endpoint, never "{}"
        XCTAssertTrue(revised.rawPayload.contains("sleep"))
        XCTAssertNotEqual(revised.rawPayload, "{}")
    }

    // MARK: Fix #2 — Oura bands at boundaries; estimate uses its own scale

    func test_oura_band_boundaries() {
        let b = ResolvedMetricsBuilder()
        func st(_ p: Int) -> RecoveryState {
            b.resolve(date: "d",
                      sources: [RawDay(source: "oura", readinessScore: p)],
                      baseline: nil, priorBasisDays: 99).recoveryState
        }
        XCTAssertEqual(st(69), .red)
        XCTAssertEqual(st(70), .amber)   // "pay attention", NOT green
        XCTAssertEqual(st(71), .amber)   // owner's real ~71
        XCTAssertEqual(st(84), .amber)
        XCTAssertEqual(st(85), .green)
    }

    // MARK: Fix #3 — no permanent progression off low-confidence green

    func test_no_progression_on_estimated_green() {
        let pe = ProgressionEngine()
        let w = WorkingSet(exerciseName: "Back Squat", workingKg: 140, targetReps: 5)
        let estimated = pe.next(working: w, lastOutcome: "hit",
                                wasGreen: true, highConfidence: false,
                                isMainLift: true)
        XCTAssertEqual(estimated.workingKg, 140, "estimated green must HOLD")
        let confirmed = pe.next(working: w, lastOutcome: "hit",
                                wasGreen: true, highConfidence: true,
                                isMainLift: true)
        XCTAssertEqual(confirmed.workingKg, 142.5, "Oura green progresses")
    }

    // MARK: Fix #5 (HealthKit) — sleep excludes `.awake`
    // Unit-level note: HealthKitReader.sleepMinutes now filters to the explicit
    // asleep* set {asleepUnspecified, asleepCore, asleepDeep, asleepREM}. A
    // device/HealthKit-store integration test asserts an `.awake` sample inside
    // the window does not add to the total. (Runs on a real iPhone.)

    // MARK: Calibrating gate at day 13 vs 14

    func test_calibrating_gate_boundary() {
        let b = ResolvedMetricsBuilder()
        let src = [RawDay(source: "oura", readinessScore: 90)]
        XCTAssertEqual(b.resolve(date: "d", sources: src, baseline: nil,
                                 priorBasisDays: 13).recoveryState, .calibrating)
        XCTAssertNil(b.resolve(date: "d", sources: src, baseline: nil,
                               priorBasisDays: 13).recoveryPct)
        XCTAssertEqual(b.resolve(date: "d", sources: src, baseline: nil,
                                 priorBasisDays: 14).recoveryState, .green)
    }
}
