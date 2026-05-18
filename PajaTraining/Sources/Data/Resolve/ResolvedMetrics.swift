import Foundation

/// The deterministic, rebuildable merge layer. Everything downstream (the
/// AdaptiveEngine, Today screen, Trends) reads ResolvedDaily — never the raw
/// daily_logs rows. Precedence is per-metric, not per-row:
///   - Oura wins  sleep / HRV / readiness  (ring-grade, worn consistently)
///   - Apple Watch wins  workout minutes / active energy
///   - "most-data-wins" when one source is missing that day
/// Recovery comes from Oura's validated Readiness when present (high
/// confidence); otherwise a simple, clearly-labeled estimate from Apple
/// Health HRV/RHR vs the owner's rolling baseline (low confidence). No score
/// at all until the baseline has enough days — that is the Calibrating state.

public struct RawDay {                     // one source's view of a day
    public let source: String              // "oura" | "apple_health"
    public var readinessScore: Int?
    public var sleepScore: Int?
    public var sleepTotalMin: Int?
    public var hrvMs: Double?
    public var restingHr: Int?
    public var workoutMin: Int?
    public init(source: String, readinessScore: Int? = nil, sleepScore: Int? = nil,
                sleepTotalMin: Int? = nil, hrvMs: Double? = nil,
                restingHr: Int? = nil, workoutMin: Int? = nil) {
        self.source = source; self.readinessScore = readinessScore
        self.sleepScore = sleepScore; self.sleepTotalMin = sleepTotalMin
        self.hrvMs = hrvMs; self.restingHr = restingHr; self.workoutMin = workoutMin
    }
}

public struct ResolvedDaily {
    public let logDate: String
    public let recoveryPct: Int?           // nil = calibrating / no basis
    public let recoveryState: RecoveryState
    public let confidence: RecoveryInput.Confidence
    public let sleepScore: Int?
    public let sleepTotalMin: Int?
    public let hrvMs: Double?
    public let restingHr: Int?
    public let workoutMin: Int?
    public let recoverySource: String?     // "oura" | "apple_health_estimate" | nil
}

/// Rolling baseline of HRV/RHR from prior resolved days (for the Apple-Health
/// estimate path). Caller supplies the trailing window.
public struct Baseline {
    public let hrvMean: Double
    public let hrvSd: Double
    public let rhrMean: Double
    public let rhrSd: Double
    public let dayCount: Int
}

public struct ResolvedMetricsBuilder {

    /// Minimum days of usable recovery basis before any score is shown.
    public static let calibrationDays = 14

    // Band thresholds (calibratable). Oura Readiness convention: ~85 optimal,
    // <70 = pay attention. We map to the engine's 3 states.
    private func state(forPct pct: Int) -> RecoveryState {
        if pct >= 70 { return .green }
        if pct >= 50 { return .amber }
        return .red
    }

    /// Build one day from whatever sources exist.
    /// - baseline: trailing baseline for the estimate path (nil if not enough days).
    /// - priorBasisDays: how many prior days already have a usable recovery basis
    ///   (drives the Calibrating gate).
    public func resolve(date: String,
                        sources: [RawDay],
                        baseline: Baseline?,
                        priorBasisDays: Int) -> ResolvedDaily {

        let oura = sources.first { $0.source == "oura" }
        let ah   = sources.first { $0.source == "apple_health" }

        // Per-metric precedence + most-data-wins.
        let sleepScore     = oura?.sleepScore     ?? ah?.sleepScore
        let sleepTotalMin  = oura?.sleepTotalMin  ?? ah?.sleepTotalMin
        let hrvMs          = oura?.hrvMs          ?? ah?.hrvMs
        let restingHr      = oura?.restingHr      ?? ah?.restingHr
        let workoutMin     = ah?.workoutMin       ?? oura?.workoutMin   // Apple Watch wins

        // --- Recovery ---
        // 1. Oura Readiness present → use it directly (high confidence).
        if let rs = oura?.readinessScore {
            // Still gate the *displayed* score behind calibration so the very
            // first days don't show a confident number with no context.
            if priorBasisDays < Self.calibrationDays {
                return ResolvedDaily(logDate: date, recoveryPct: nil,
                                     recoveryState: .calibrating,
                                     confidence: .high,
                                     sleepScore: sleepScore, sleepTotalMin: sleepTotalMin,
                                     hrvMs: hrvMs, restingHr: restingHr,
                                     workoutMin: workoutMin, recoverySource: "oura")
            }
            return ResolvedDaily(logDate: date, recoveryPct: rs,
                                 recoveryState: state(forPct: rs),
                                 confidence: .high,
                                 sleepScore: sleepScore, sleepTotalMin: sleepTotalMin,
                                 hrvMs: hrvMs, restingHr: restingHr,
                                 workoutMin: workoutMin, recoverySource: "oura")
        }

        // 2. No Oura. Estimate from Apple Health HRV/RHR vs baseline (LOW
        //    confidence, clearly labeled upstream). Needs a baseline.
        if let b = baseline, let hrv = hrvMs, let rhr = restingHr,
           b.dayCount >= Self.calibrationDays, b.hrvSd > 0, b.rhrSd > 0 {
            // Higher HRV vs baseline = better; lower RHR = better.
            let zHrv = (hrv - b.hrvMean) / b.hrvSd
            let zRhr = (b.rhrMean - Double(rhr)) / b.rhrSd
            let z = 0.7 * zHrv + 0.3 * zRhr
            // Logistic squash to 0..100.
            let pct = Int((100.0 / (1.0 + exp(-1.0 * z))).rounded())
            return ResolvedDaily(logDate: date, recoveryPct: pct,
                                 recoveryState: state(forPct: pct),
                                 confidence: .low,
                                 sleepScore: sleepScore, sleepTotalMin: sleepTotalMin,
                                 hrvMs: hrvMs, restingHr: restingHr,
                                 workoutMin: workoutMin,
                                 recoverySource: "apple_health_estimate")
        }

        // 3. Not enough basis yet → Calibrating (if some data) or unknown.
        let hasAnything = !sources.isEmpty
        return ResolvedDaily(logDate: date, recoveryPct: nil,
                             recoveryState: hasAnything ? .calibrating : .unknown,
                             confidence: hasAnything ? .low : .none,
                             sleepScore: sleepScore, sleepTotalMin: sleepTotalMin,
                             hrvMs: hrvMs, restingHr: restingHr,
                             workoutMin: workoutMin, recoverySource: nil)
    }

    /// Compute a trailing baseline from prior resolved days that had real
    /// HRV/RHR. Pass the last ~30 days; returns nil if too few.
    public func baseline(from days: [ResolvedDaily]) -> Baseline? {
        let hrv = days.compactMap { $0.hrvMs }
        let rhr = days.compactMap { $0.restingHr.map(Double.init) }
        guard hrv.count >= Self.calibrationDays, rhr.count >= Self.calibrationDays
        else { return nil }
        func meanSd(_ v: [Double]) -> (Double, Double) {
            let m = v.reduce(0, +) / Double(v.count)
            let varc = v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(max(1, v.count - 1))
            return (m, varc.squareRoot())
        }
        let (hm, hs) = meanSd(hrv)
        let (rm, rs) = meanSd(rhr)
        return Baseline(hrvMean: hm, hrvSd: hs == 0 ? 1 : hs,
                        rhrMean: rm, rhrSd: rs == 0 ? 1 : rs,
                        dayCount: min(hrv.count, rhr.count))
    }
}
