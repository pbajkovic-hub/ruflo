import Foundation
import GRDB

struct WeeklyLogRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "weekly_logs"
    var id: String
    var userId: String
    var weekStartDate: String
    var sessionsDone: Int?
    var totalVolumeKg: Double?
    var avgRecoveryPct: Double?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case weekStartDate = "week_start_date"
        case sessionsDone = "sessions_done"
        case totalVolumeKg = "total_volume_kg"
        case avgRecoveryPct = "avg_recovery_pct"
        case notes
    }
}

struct DailyLogRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "daily_logs"
    var id: String
    var userId: String
    var logDate: String
    var source: String
    var sourceRecordId: String?
    var sourceUpdatedAt: String?
    var readinessScore: Int?
    var sleepScore: Int?
    var sleepTotalMin: Int?
    var hrvMs: Double?
    var restingHr: Int?
    var tempDeviation: Double?
    var steps: Int?
    var activeKcal: Int?
    var workoutMin: Int?
    var rawPayload: String?
    var syncedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case logDate = "log_date"
        case source
        case sourceRecordId = "source_record_id"
        case sourceUpdatedAt = "source_updated_at"
        case readinessScore = "readiness_score"
        case sleepScore = "sleep_score"
        case sleepTotalMin = "sleep_total_min"
        case hrvMs = "hrv_ms"
        case restingHr = "resting_hr"
        case tempDeviation = "temp_deviation"
        case steps
        case activeKcal = "active_kcal"
        case workoutMin = "workout_min"
        case rawPayload = "raw_payload"
        case syncedAt = "synced_at"
    }
}

struct ResolvedDailyRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "resolved_daily_metrics"
    var userId: String
    var logDate: String
    var recoveryPct: Int?
    var recoveryState: String?
    var confidence: String
    var sleepScore: Int?
    var sleepTotalMin: Int?
    var hrvMs: Double?
    var restingHr: Int?
    var workoutMin: Int?
    var recoverySource: String?
    var rebuiltAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case logDate = "log_date"
        case recoveryPct = "recovery_pct"
        case recoveryState = "recovery_state"
        case confidence
        case sleepScore = "sleep_score"
        case sleepTotalMin = "sleep_total_min"
        case hrvMs = "hrv_ms"
        case restingHr = "resting_hr"
        case workoutMin = "workout_min"
        case recoverySource = "recovery_source"
        case rebuiltAt = "rebuilt_at"
    }
}

struct BodyCompositionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "body_composition"
    var id: String
    var userId: String
    var measuredOn: String
    var source: String
    var weightKg: Double?
    var bodyFatPct: Double?
    var skeletalMuscleMassKg: Double?
    var leanBodyMassKg: Double?
    var totalBodyWaterL: Double?
    var visceralFatLevel: Double?
    var bmrKcal: Int?
    var bmi: Double?
    var inbodyScore: Int?
    var segmentalLeanJson: String?
    var rawPayload: String?
    var notes: String?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case measuredOn = "measured_on"
        case source
        case weightKg = "weight_kg"
        case bodyFatPct = "body_fat_pct"
        case skeletalMuscleMassKg = "skeletal_muscle_mass_kg"
        case leanBodyMassKg = "lean_body_mass_kg"
        case totalBodyWaterL = "total_body_water_l"
        case visceralFatLevel = "visceral_fat_level"
        case bmrKcal = "bmr_kcal"
        case bmi
        case inbodyScore = "inbody_score"
        case segmentalLeanJson = "segmental_lean_json"
        case rawPayload = "raw_payload"
        case notes
        case createdAt = "created_at"
    }
}
