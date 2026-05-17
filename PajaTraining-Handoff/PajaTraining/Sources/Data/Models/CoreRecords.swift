import Foundation
import GRDB

struct UserRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "users"
    var id: String
    var displayName: String
    var timezone: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case timezone
        case createdAt = "created_at"
    }
}

struct ConnectionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "connections"
    var id: String
    var userId: String
    var provider: String
    var status: String
    var keychainRef: String?
    var lastSyncAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case provider
        case status
        case keychainRef = "keychain_ref"
        case lastSyncAt = "last_sync_at"
    }
}

struct ExerciseRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "exercises"
    var id: String
    var userId: String?
    var name: String
    var category: String?
    var isMainLift: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case category
        case isMainLift = "is_main_lift"
    }
}

struct ProgramRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "program"
    var id: String
    var userId: String
    var split: String
    var templateKey: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case split
        case templateKey = "template_key"
        case createdAt = "created_at"
    }
}

struct ProgramInstanceRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "program_instance"
    var id: String
    var userId: String
    var programId: String
    var status: String
    var rotationIndex: Int
    var weekInBlock: Int
    var startedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case programId = "program_id"
        case status
        case rotationIndex = "rotation_index"
        case weekInBlock = "week_in_block"
        case startedAt = "started_at"
    }
}

struct LiftProgressRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "lift_progress"
    var id: String
    var userId: String
    var exerciseId: String
    var workingKg: Double
    var targetReps: Int
    var lastOutcome: String?
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseId = "exercise_id"
        case workingKg = "working_kg"
        case targetReps = "target_reps"
        case lastOutcome = "last_outcome"
        case updatedAt = "updated_at"
    }
}
