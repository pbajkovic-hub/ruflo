import Foundation

/// The product. Deterministic — NOT an LLM. Given today's resolved recovery,
/// the active program position, and the owner's working weights, it produces
/// the exact session to do today plus a one-line "why". The (deferred) LLM
/// coach will later only *explain* this output; it never replaces it.

public enum RecoveryState: String, Codable { case green, amber, red, calibrating, unknown }

public struct RecoveryInput {
    public let state: RecoveryState
    public let pct: Int?            // nil while calibrating / no data
    public let confidence: Confidence
    public enum Confidence: String { case high, low, none }
}

public struct PrescribedSet {
    public let setNumber: Int
    public let reps: Int
    public let kg: Double
    public let isBackoff: Bool
}

public struct PrescribedExercise {
    public let name: String
    public let isMainLift: Bool
    public let sets: [PrescribedSet]
}

public struct PrescribedSession {
    public let dayLabel: String            // "Push" / "Recovery (mobility)" ...
    public let exercises: [PrescribedExercise]
    public let why: String                 // the single sentence shown on Today
    public let recoveryState: RecoveryState
    public let recoveryPct: Int?
}

/// Per-exercise working numbers (mirrors lift_progress rows).
public struct WorkingSet {
    public let exerciseName: String
    public let workingKg: Double
    public let targetReps: Int
}

public struct AdaptiveEngine {

    /// Round to the nearest loadable increment (kg). 2.5 kg by default.
    private func round(_ kg: Double, to step: Double = 2.5) -> Double {
        (kg / step).rounded() * step
    }

    private func working(_ name: String, _ table: [String: WorkingSet]) -> WorkingSet? {
        table[name]
    }

    /// Produce today's session.
    /// - isDeloadWeek: program_instance says this is the periodic light week.
    public func prescribe(day: TemplateDay,
                          recovery: RecoveryInput,
                          working table: [String: WorkingSet],
                          isDeloadWeek: Bool) -> PrescribedSession {

        // 1. Calibrating: NEVER show a number or push hard. Give the planned
        //    session at a conservative cap, and say so honestly.
        if recovery.state == .calibrating {
            return build(day: day, table: table,
                         volumeFactor: 0.85, intensityFactor: 0.90,
                         dropBackoff: true, swapToRecovery: false,
                         why: "Still learning your baseline — moderate session, no hard pushing yet.",
                         recovery: recovery)
        }

        // 2. No usable data (forgot the ring + no watch): degrade gracefully.
        if recovery.state == .unknown || recovery.confidence == .none {
            return build(day: day, table: table,
                         volumeFactor: 0.85, intensityFactor: 0.90,
                         dropBackoff: true, swapToRecovery: false,
                         why: "No recovery data today — keeping it moderate to be safe.",
                         recovery: recovery)
        }

        // 3. Deload week overrides the bands downward but keeps the split.
        if isDeloadWeek {
            return build(day: day, table: table,
                         volumeFactor: 0.5, intensityFactor: 0.7,
                         dropBackoff: true, swapToRecovery: false,
                         why: "Planned deload week — light and easy, this is by design.",
                         recovery: recovery)
        }

        // 4. The recovery bands.
        switch recovery.state {
        case .red:
            // Protect: swap the lifting day for mobility/Z2 recovery work.
            return build(day: day, table: table,
                         volumeFactor: 0, intensityFactor: 0,
                         dropBackoff: true, swapToRecovery: true,
                         why: "Recovery \(pctText(recovery)) — red. Today is active recovery, not lifting.",
                         recovery: recovery)
        case .amber:
            // Maintain: full main lifts, trimmed back-off sets, capped intensity.
            return build(day: day, table: table,
                         volumeFactor: 0.8, intensityFactor: 0.93,
                         dropBackoff: true, swapToRecovery: false,
                         why: "Recovery \(pctText(recovery)) — amber. Main work stays, back-off sets dropped, ease the last sets.",
                         recovery: recovery)
        case .green:
            // Build: full session; progression is applied by ProgressionEngine
            // before this runs (table already holds the bumped working weight).
            return build(day: day, table: table,
                         volumeFactor: 1.0, intensityFactor: 1.0,
                         dropBackoff: false, swapToRecovery: false,
                         why: "Recovery \(pctText(recovery)) — green. Full session, progression is on.",
                         recovery: recovery)
        case .calibrating, .unknown:
            // handled above
            return build(day: day, table: table,
                         volumeFactor: 0.85, intensityFactor: 0.9,
                         dropBackoff: true, swapToRecovery: false,
                         why: "Moderate session.", recovery: recovery)
        }
    }

    private func pctText(_ r: RecoveryInput) -> String {
        guard let p = r.pct else { return "(no score)" }
        return r.confidence == .low ? "~\(p)% (estimated)" : "\(p)%"
    }

    private func build(day: TemplateDay,
                        table: [String: WorkingSet],
                        volumeFactor: Double,
                        intensityFactor: Double,
                        dropBackoff: Bool,
                        swapToRecovery: Bool,
                        why: String,
                        recovery: RecoveryInput) -> PrescribedSession {

        if swapToRecovery {
            return PrescribedSession(
                dayLabel: "Recovery (mobility + Z2)",
                exercises: [PrescribedExercise(
                    name: "Easy cardio 20–30 min + full-body mobility",
                    isMainLift: false, sets: [])],
                why: why, recoveryState: recovery.state, recoveryPct: recovery.pct)
        }

        var out: [PrescribedExercise] = []
        for slot in day.slots {
            let setCount = max(1, Int((Double(slot.sets) * volumeFactor).rounded()))
            let w = working(slot.name, table)
            let baseKg = (w?.workingKg ?? 0) * slot.intensityPct * intensityFactor
            let reps = w?.targetReps ?? slot.reps

            var sets: [PrescribedSet] = []
            for i in 1...setCount {
                let isBackoff = slot.hasBackoffSet && i == setCount && !dropBackoff
                let kg = round(isBackoff ? baseKg * 0.85 : baseKg)
                sets.append(PrescribedSet(setNumber: i, reps: reps, kg: kg,
                                          isBackoff: isBackoff))
            }
            out.append(PrescribedExercise(name: slot.name,
                                          isMainLift: slot.isMainLift, sets: sets))
        }
        return PrescribedSession(dayLabel: day.label, exercises: out, why: why,
                                 recoveryState: recovery.state,
                                 recoveryPct: recovery.pct)
    }
}

/// Applies progressive overload AFTER a session is logged. Kept separate so
/// the prescription is pure and testable. Only progresses on green + a hit.
public struct ProgressionEngine {
    public func next(working: WorkingSet,
                     lastOutcome: String,
                     wasGreen: Bool,
                     isMainLift: Bool) -> WorkingSet {
        switch lastOutcome {
        case "hit" where wasGreen:
            let step = isMainLift ? 2.5 : 1.25
            return WorkingSet(exerciseName: working.exerciseName,
                              workingKg: working.workingKg + step,
                              targetReps: working.targetReps)
        case "missed":
            // Back off 10% after a clear miss (auto-deload that lift).
            return WorkingSet(exerciseName: working.exerciseName,
                              workingKg: (working.workingKg * 0.9 / 2.5).rounded() * 2.5,
                              targetReps: working.targetReps)
        default:
            return working   // amber/red/skipped: hold, don't progress
        }
    }
}
