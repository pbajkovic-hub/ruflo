import Foundation
import GRDB

struct SessionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "sessions"
    var id: String
    var userId: String
    var programInstanceId: String?
    var sessionDate: String
    var dayLabel: String?
    var status: String
    var recoveryState: String?
    var recoveryPct: Int?
    var prescriptionWhy: String?
    var deletedAt: String?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case programInstanceId = "program_instance_id"
        case sessionDate = "session_date"
        case dayLabel = "day_label"
        case status
        case recoveryState = "recovery_state"
        case recoveryPct = "recovery_pct"
        case prescriptionWhy = "prescription_why"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }
}

struct SessionExerciseRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "session_exercises"
    var id: String
    var sessionId: String
    var exerciseId: String
    var orderIndex: Int

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case exerciseId = "exercise_id"
        case orderIndex = "order_index"
    }
}

struct SetRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "sets"
    var id: String
    var sessionExerciseId: String
    var setNumber: Int
    var targetReps: Int?
    var targetKg: Double?
    var doneReps: Int?
    var doneKg: Double?
    var rpe: Double?
    var isWarmup: Bool
    var isBackoff: Bool
    var completed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case sessionExerciseId = "session_exercise_id"
        case setNumber = "set_number"
        case targetReps = "target_reps"
        case targetKg = "target_kg"
        case doneReps = "done_reps"
        case doneKg = "done_kg"
        case rpe
        case isWarmup = "is_warmup"
        case isBackoff = "is_backoff"
        case completed
    }
}

struct GoalRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "goals"
    var id: String
    var userId: String
    var title: String
    var metric: String
    var unit: String
    var targetValue: Double
    var targetDate: String?
    var status: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case metric
        case unit
        case targetValue = "target_value"
        case targetDate = "target_date"
        case status
        case createdAt = "created_at"
    }
}

struct GoalProgressRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "goal_progress"
    var id: String
    var goalId: String
    var recordedAt: String
    var value: Double
    var source: String

    enum CodingKeys: String, CodingKey {
        case id
        case goalId = "goal_id"
        case recordedAt = "recorded_at"
        case value
        case source
    }
}
