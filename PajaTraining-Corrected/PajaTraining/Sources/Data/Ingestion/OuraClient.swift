import Foundation

/// Oura API v2 client for PERSONAL use: authenticates with a Personal Access
/// Token (no OAuth, no webhooks — those are productization). Polls a date
/// window on app-open / background refresh. Implements every correction from
/// the design review §6: physiology from `sleep` not `daily_sleep`, one
/// canonical sleep score, nullable scores, multiple sleep rows/day, 429
/// backoff, 401/403 states, revision-aware upsert.

public struct OuraDailyLog {
    public let logDate: String            // "YYYY-MM-DD"
    public let sourceRecordId: String?    // Oura document id (revision key)
    public let sourceUpdatedAt: String?   // revision marker
    public var readinessScore: Int?       // nullable per spec
    public var sleepScore: Int?           // the ONE canonical score (daily_sleep.score)
    public var sleepTotalMin: Int?
    public var hrvMs: Double?
    public var restingHr: Int?
    public var tempDeviation: Double?
    public var steps: Int?
    public var activeKcal: Int?
    public var workoutMin: Int?
    public let rawPayload: String
}

public enum OuraError: Error, Equatable {
    case tokenInvalid          // 401 — re-enter token
    case membershipLapsed      // 403 — Oura membership expired, no data coming
    case rateLimited           // 429 — backed off, try later
    case transport(String)
}

/// Abstracts persistence so the polling/merge logic is unit-testable off-device.
public protocol DailyLogStore {
    /// Existing row for (date, source 'oura'); nil if none.
    func existingOura(date: String) throws -> (recordId: String?, updatedAt: String?)?
    /// Insert or update. Implementation does last-write-wins on updatedAt.
    func upsertOura(_ log: OuraDailyLog) throws
}

public struct OuraClient {
    private let base = URL(string: "https://api.ouraring.com/v2/usercollection")!
    private let token: String                 // from iOS Keychain, never persisted in SQLite
    private let session: URLSession
    private let store: DailyLogStore

    public init(token: String, store: DailyLogStore, session: URLSession = .shared) {
        self.token = token
        self.store = store
        self.session = session
    }

    // MARK: Public entry point

    /// Poll [startDate, endDate] (ISO dates) and upsert revised rows.
    public func sync(from startDate: String, to endDate: String) async throws {
        async let readiness = fetchAll("daily_readiness", startDate, endDate)
        async let dailySleep = fetchAll("daily_sleep", startDate, endDate)
        async let sleep = fetchAll("sleep", startDate, endDate)
        async let activity = fetchAll("daily_activity", startDate, endDate)
        let (rd, ds, sl, ac) = try await (readiness, dailySleep, sleep, activity)

        // Build one merged OuraDailyLog per day.
        var byDay: [String: OuraDailyLog] = [:]

        func ts(_ d: [String: Any]) -> String? { d["timestamp"] as? String }

        for r in rd {
            let day = r["day"] as? String ?? ""
            guard !day.isEmpty else { continue }
            var log = byDay[day] ?? blank(day)
            log.readinessScore = r["score"] as? Int          // may be null → stays nil
            log.tempDeviation = (r["temperature_deviation"] as? NSNumber)?.doubleValue
            byDay[day] = log.merging(endpoint: "daily_readiness",
                                     recordId: r["id"] as? String,
                                     updatedAt: ts(r), raw: r)
        }
        for d in ds {
            let day = d["day"] as? String ?? ""
            guard !day.isEmpty else { continue }
            var log = byDay[day] ?? blank(day)
            log.sleepScore = d["score"] as? Int               // THE canonical sleep score
            byDay[day] = log.merging(endpoint: "daily_sleep",
                                     recordId: d["id"] as? String,
                                     updatedAt: ts(d), raw: d)
        }
        // `sleep` has multiple rows/day with a `type`. Take the main nightly
        // sleep (longest of type sleep/long_sleep); skip `deleted`.
        for grouped in Dictionary(grouping: sl, by: { $0["day"] as? String ?? "" }) {
            let day = grouped.key
            guard !day.isEmpty else { continue }
            let candidates = grouped.value.filter {
                let t = $0["type"] as? String ?? "sleep"
                return t != "deleted" && (t == "sleep" || t == "long_sleep")
            }
            guard let main = candidates.max(by: {
                (($0["total_sleep_duration"] as? Int) ?? 0) <
                (($1["total_sleep_duration"] as? Int) ?? 0)
            }) else { continue }
            var log = byDay[day] ?? blank(day)
            if let secs = main["total_sleep_duration"] as? Int {
                log.sleepTotalMin = secs / 60
            }
            log.hrvMs = (main["average_hrv"] as? NSNumber)?.doubleValue
            log.restingHr = main["lowest_heart_rate"] as? Int   // NOT average_heart_rate
            byDay[day] = log.merging(endpoint: "sleep",
                                     recordId: main["id"] as? String,
                                     updatedAt: ts(main) ?? (main["bedtime_end"] as? String),
                                     raw: main)
        }
        for a in ac {
            let day = a["day"] as? String ?? ""
            guard !day.isEmpty else { continue }
            var log = byDay[day] ?? blank(day)
            log.steps = a["steps"] as? Int
            log.activeKcal = a["active_calories"] as? Int
            byDay[day] = log.merging(endpoint: "daily_activity",
                                     recordId: a["id"] as? String,
                                     updatedAt: ts(a), raw: a)
        }

        // Revision-aware upsert: only write if new or Oura revised the record.
        for (_, log) in byDay {
            if let existing = try store.existingOura(date: log.logDate),
               let exTs = existing.updatedAt, let newTs = log.sourceUpdatedAt,
               newTs <= exTs {
                continue   // nothing newer from Oura
            }
            try store.upsertOura(log)
        }
    }

    // MARK: Fetch with pagination + backoff

    private func fetchAll(_ path: String, _ start: String, _ end: String) async throws -> [[String: Any]] {
        var results: [[String: Any]] = []
        var nextToken: String? = nil
        repeat {
            var comps = URLComponents(url: base.appendingPathComponent(path),
                                      resolvingAgainstBaseURL: false)!
            var q = [URLQueryItem(name: "start_date", value: start),
                     URLQueryItem(name: "end_date", value: end)]
            if let t = nextToken { q.append(URLQueryItem(name: "next_token", value: t)) }
            comps.queryItems = q
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, resp) = try await sendWithBackoff(req)
            guard let http = resp as? HTTPURLResponse else {
                throw OuraError.transport("no http response")
            }
            switch http.statusCode {
            case 200: break
            case 401: throw OuraError.tokenInvalid
            case 403: throw OuraError.membershipLapsed
            case 429: throw OuraError.rateLimited
            default:  throw OuraError.transport("status \(http.statusCode)")
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            results += (json["data"] as? [[String: Any]]) ?? []
            nextToken = json["next_token"] as? String
        } while nextToken != nil
        return results
    }

    /// One retry with exponential backoff on 429 (respecting Retry-After).
    private func sendWithBackoff(_ req: URLRequest, attempt: Int = 0) async throws -> (Data, URLResponse) {
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 429, attempt < 3 {
            let retryAfter = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "")
                ?? pow(2.0, Double(attempt + 1))
            try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
            return try await sendWithBackoff(req, attempt: attempt + 1)
        }
        return (data, resp)
    }

    private func blank(_ day: String) -> OuraDailyLog {
        OuraDailyLog(logDate: day, sourceRecordId: nil, sourceUpdatedAt: nil,
                     readinessScore: nil, sleepScore: nil, sleepTotalMin: nil,
                     hrvMs: nil, restingHr: nil, tempDeviation: nil,
                     steps: nil, activeKcal: nil, workoutMin: nil, rawPayload: "{}")
    }
}

private extension OuraDailyLog {
    /// Merge one Oura endpoint's row into the per-day log: accumulate EVERY
    /// endpoint's raw JSON under its own key (nothing discarded — fixes the
    /// no-readiness-day raw_payload loss), keep the first non-nil record id,
    /// and carry the MAX timestamp across all endpoints so a revision to ANY
    /// endpoint (sleep-only, activity-only, …) re-triggers the day's upsert.
    func merging(endpoint: String,
                 recordId: String?,
                 updatedAt: String?,
                 raw: [String: Any]) -> OuraDailyLog {
        var parts = (try? JSONSerialization.jsonObject(with: Data(rawPayload.utf8)))
            as? [String: Any] ?? [:]
        parts[endpoint] = raw
        let payload = (try? JSONSerialization.data(withJSONObject: parts))
            .flatMap { String(data: $0, encoding: .utf8) } ?? rawPayload
        let maxTs: String?
        switch (sourceUpdatedAt, updatedAt) {
        case let (a?, b?): maxTs = Swift.max(a, b)   // ISO-8601 sorts lexically
        case let (a?, nil): maxTs = a
        case let (nil, b?): maxTs = b
        default:            maxTs = nil
        }
        return OuraDailyLog(logDate: logDate,
                            sourceRecordId: sourceRecordId ?? recordId,
                            sourceUpdatedAt: maxTs,
                            readinessScore: readinessScore, sleepScore: sleepScore,
                            sleepTotalMin: sleepTotalMin, hrvMs: hrvMs,
                            restingHr: restingHr, tempDeviation: tempDeviation,
                            steps: steps, activeKcal: activeKcal,
                            workoutMin: workoutMin, rawPayload: payload)
    }
}
