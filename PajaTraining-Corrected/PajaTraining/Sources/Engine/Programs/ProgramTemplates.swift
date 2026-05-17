import Foundation

/// Built-in program templates. The owner trains push/pull/legs and upper/lower,
/// so v1 ships exactly these two. Templates are code (stable, versioned by key);
/// the adaptive engine modulates them by recovery — it never invents exercises.

public enum SplitType: String, Codable { case ppl, upperLower = "upper_lower" }

public enum ExerciseCategory: String, Codable {
    case push, pull, legs, upper, lower, core, accessory
}

/// One prescribed slot inside a template day. `intensityPct` is % of the
/// owner's working weight for that lift (working weight lives in lift_progress).
public struct ExerciseSlot: Codable {
    public let name: String
    public let category: ExerciseCategory
    public let isMainLift: Bool
    public let sets: Int
    public let reps: Int
    public let intensityPct: Double          // 1.0 == working weight
    public let hasBackoffSet: Bool           // first thing trimmed on amber days
}

public struct TemplateDay: Codable {
    public let label: String                 // "Push", "Upper", ...
    public let slots: [ExerciseSlot]
}

public struct ProgramTemplate: Codable {
    public let key: String                   // 'ppl.v1' / 'ul.v1'
    public let split: SplitType
    public let rotation: [TemplateDay]       // cycled by program_instance.rotation_index
    public let deloadEveryNWeeks: Int        // forced light week cadence
}

public enum ProgramTemplates {

    /// Push / Pull / Legs — 3-day rotation, deload every 4th week.
    public static let ppl = ProgramTemplate(
        key: "ppl.v1",
        split: .ppl,
        deloadEveryNWeeks: 4,
        rotation: [
            TemplateDay(label: "Push", slots: [
                .init(name: "Barbell Bench Press", category: .push, isMainLift: true,
                      sets: 4, reps: 5, intensityPct: 1.0, hasBackoffSet: true),
                .init(name: "Overhead Press", category: .push, isMainLift: true,
                      sets: 3, reps: 6, intensityPct: 1.0, hasBackoffSet: true),
                .init(name: "Incline Dumbbell Press", category: .push, isMainLift: false,
                      sets: 3, reps: 10, intensityPct: 0.7, hasBackoffSet: false),
                .init(name: "Triceps Pushdown", category: .accessory, isMainLift: false,
                      sets: 3, reps: 12, intensityPct: 0.6, hasBackoffSet: false),
            ]),
            TemplateDay(label: "Pull", slots: [
                .init(name: "Deadlift", category: .pull, isMainLift: true,
                      sets: 3, reps: 4, intensityPct: 1.0, hasBackoffSet: true),
                .init(name: "Weighted Pull-up", category: .pull, isMainLift: true,
                      sets: 4, reps: 6, intensityPct: 1.0, hasBackoffSet: true),
                .init(name: "Barbell Row", category: .pull, isMainLift: false,
                      sets: 3, reps: 8, intensityPct: 0.8, hasBackoffSet: false),
                .init(name: "Face Pull", category: .accessory, isMainLift: false,
                      sets: 3, reps: 15, intensityPct: 0.5, hasBackoffSet: false),
            ]),
            TemplateDay(label: "Legs", slots: [
                .init(name: "Back Squat", category: .legs, isMainLift: true,
                      sets: 4, reps: 5, intensityPct: 1.0, hasBackoffSet: true),
                .init(name: "Romanian Deadlift", category: .legs, isMainLift: true,
                      sets: 3, reps: 8, intensityPct: 0.85, hasBackoffSet: true),
                .init(name: "Leg Press", category: .legs, isMainLift: false,
                      sets: 3, reps: 12, intensityPct: 0.7, hasBackoffSet: false),
                .init(name: "Standing Calf Raise", category: .accessory, isMainLift: false,
                      sets: 4, reps: 12, intensityPct: 0.6, hasBackoffSet: false),
            ]),
        ]
    )

    /// Upper / Lower — 2-day rotation, deload every 5th week.
    public static let upperLower = ProgramTemplate(
        key: "ul.v1",
        split: .upperLower,
        deloadEveryNWeeks: 5,
        rotation: [
            TemplateDay(label: "Upper", slots: [
                .init(name: "Barbell Bench Press", category: .upper, isMainLift: true,
                      sets: 4, reps: 6, intensityPct: 1.0, hasBackoffSet: true),
                .init(name: "Barbell Row", category: .upper, isMainLift: true,
                      sets: 4, reps: 6, intensityPct: 1.0, hasBackoffSet: true),
                .init(name: "Overhead Press", category: .upper, isMainLift: false,
                      sets: 3, reps: 8, intensityPct: 0.8, hasBackoffSet: false),
                .init(name: "Lat Pulldown", category: .accessory, isMainLift: false,
                      sets: 3, reps: 12, intensityPct: 0.6, hasBackoffSet: false),
            ]),
            TemplateDay(label: "Lower", slots: [
                .init(name: "Back Squat", category: .lower, isMainLift: true,
                      sets: 4, reps: 5, intensityPct: 1.0, hasBackoffSet: true),
                .init(name: "Deadlift", category: .lower, isMainLift: true,
                      sets: 3, reps: 4, intensityPct: 1.0, hasBackoffSet: true),
                .init(name: "Leg Press", category: .lower, isMainLift: false,
                      sets: 3, reps: 10, intensityPct: 0.7, hasBackoffSet: false),
                .init(name: "Hanging Leg Raise", category: .core, isMainLift: false,
                      sets: 3, reps: 12, intensityPct: 0.0, hasBackoffSet: false),
            ]),
        ]
    )

    public static func template(forKey key: String) -> ProgramTemplate? {
        switch key {
        case ppl.key: return ppl
        case upperLower.key: return upperLower
        default: return nil
        }
    }
}
