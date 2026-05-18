import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Apple Health reader. iOS-only (HealthKit). Produces:
///  - daily logs (source = apple_health): HRV SDNN, resting HR, sleep minutes,
///    workout minutes, active energy, steps — the fallback when Oura is absent
///    (owner sometimes forgets the watch/ring).
///  - body-composition rows when a nutrition/InBody app writes weight /
///    body-fat % / lean mass into Apple Health (the v1 InBody path).
///
/// Compiles only where HealthKit exists; the shape is portable for review.

public struct AppleHealthDailyLog {
    public let logDate: String
    public var hrvMs: Double?
    public var restingHr: Int?
    public var sleepTotalMin: Int?
    public var workoutMin: Int?
    public var activeKcal: Int?
    public var steps: Int?
    public let rawPayload: String
}

public struct AppleHealthBodyComposition {
    public let measuredOn: String
    public var weightKg: Double?
    public var bodyFatPct: Double?
    public var leanBodyMassKg: Double?
}

#if canImport(HealthKit)
public final class HealthKitReader {
    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>()
        if let t = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bodyMass) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .leanBodyMass) { s.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(t) }
        s.insert(HKObjectType.workoutType())
        return s
    }

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Daily log for a single local calendar day [dayStart, dayEnd).
    public func dailyLog(dayStart: Date, dayEnd: Date, isoDay: String) async -> AppleHealthDailyLog {
        async let hrv = avgQuantity(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli),
                                    start: dayStart, end: dayEnd)
        async let rhr = avgQuantity(.restingHeartRate,
                                    unit: HKUnit.count().unitDivided(by: .minute()),
                                    start: dayStart, end: dayEnd)
        async let kcal = sumQuantity(.activeEnergyBurned, unit: .kilocalorie(),
                                     start: dayStart, end: dayEnd)
        async let steps = sumQuantity(.stepCount, unit: .count(),
                                      start: dayStart, end: dayEnd)
        async let workoutMin = workoutMinutes(start: dayStart, end: dayEnd)
        async let sleepMin = sleepMinutes(start: dayStart.addingTimeInterval(-12*3600), end: dayEnd)

        let (h, r, k, s, w, sl) = await (hrv, rhr, kcal, steps, workoutMin, sleepMin)
        return AppleHealthDailyLog(
            logDate: isoDay,
            hrvMs: h, restingHr: r.map { Int($0.rounded()) },
            sleepTotalMin: sl, workoutMin: w,
            activeKcal: k.map { Int($0.rounded()) }, steps: s.map { Int($0.rounded()) },
            rawPayload: "{\"source\":\"apple_health\"}")
    }

    /// Latest body-composition snapshot in [start,end) — used weekly, not daily.
    public func bodyComposition(start: Date, end: Date, measuredOn: String) async -> AppleHealthBodyComposition {
        async let wt = latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo), start: start, end: end)
        async let bf = latestQuantity(.bodyFatPercentage, unit: .percent(), start: start, end: end)
        async let lean = latestQuantity(.leanBodyMass, unit: .gramUnit(with: .kilo), start: start, end: end)
        let (w, f, l) = await (wt, bf, lean)
        return AppleHealthBodyComposition(measuredOn: measuredOn,
                                          weightKg: w,
                                          bodyFatPct: f.map { $0 * 100 },
                                          leanBodyMassKg: l)
    }

    // MARK: - Query helpers

    private func avgQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                             start: Date, end: Date) async -> Double? {
        await statistic(id, .discreteAverage, unit: unit, start: start, end: end)
    }
    private func sumQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                             start: Date, end: Date) async -> Double? {
        await statistic(id, .cumulativeSum, unit: unit, start: start, end: end)
    }

    private func statistic(_ id: HKQuantityTypeIdentifier, _ opt: HKStatisticsOptions,
                           unit: HKUnit, start: Date, end: Date) async -> Double? {
        guard let qt = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: qt, quantitySamplePredicate: pred,
                                      options: opt) { _, stats, _ in
                let qv = opt == .cumulativeSum ? stats?.sumQuantity()
                                               : stats?.averageQuantity()
                cont.resume(returning: qv?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    private func latestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                                start: Date, end: Date) async -> Double? {
        guard let qt = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: qt, predicate: pred, limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: v)
            }
            store.execute(q)
        }
    }

    private func workoutMinutes(start: Date, end: Date) async -> Int? {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                let total = (s as? [HKWorkout])?.reduce(0) { $0 + $1.duration } ?? 0
                cont.resume(returning: total > 0 ? Int(total / 60) : nil)
            }
            store.execute(q)
        }
    }

    private func sleepMinutes(start: Date, end: Date) async -> Int? {
        guard let st = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: st, predicate: pred,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                let asleep = (s as? [HKCategorySample])?.filter {
                    $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue
                } ?? []
                let secs = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: secs > 0 ? Int(secs / 60) : nil)
            }
            store.execute(q)
        }
    }
}
#endif
