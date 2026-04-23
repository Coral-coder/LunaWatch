import Foundation
import HealthKit

struct SleepRecord: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
    var hoursMinutes: String {
        let h = Int(duration) / 3600
        let m = Int(duration) % 3600 / 60
        return "\(h)h \(m)m"
    }
}

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()
    private let stepType  = HKQuantityType(.stepCount)
    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let calType   = HKQuantityType(.activeEnergyBurned)
    private let hrType    = HKQuantityType(.heartRate)

    @Published var isAuthorized = false
    @Published var authError: String?
    @Published var todaySteps: Int = 0
    @Published var weekSteps: [(date: Date, count: Int)] = []
    @Published var lastSleep: SleepRecord?
    @Published var recentSleep: [SleepRecord] = []
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            authError = "HealthKit is not available on this device"; return
        }
        let read: Set<HKObjectType>   = [stepType, sleepType, calType, hrType]
        let share: Set<HKSampleType>  = [stepType, sleepType]
        store.requestAuthorization(toShare: share, read: read) { [weak self] granted, err in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                if granted { self?.fetchAll() }
                else { self?.authError = err?.localizedDescription ?? "Authorization denied" }
            }
        }
    }

    func fetchAll() {
        fetchTodaySteps()
        fetchWeekSteps()
        fetchSleep()
        fetchHeartRate()
        fetchCalories()
    }

    // MARK: - Steps

    func fetchTodaySteps() {
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        store.execute(HKStatisticsQuery(quantityType: stepType,
                                        quantitySamplePredicate: pred,
                                        options: .cumulativeSum) { [weak self] _, result, _ in
            DispatchQueue.main.async {
                self?.todaySteps = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            }
        })
    }

    func fetchWeekSteps() {
        let cal = Calendar.current
        guard let weekStart = cal.date(byAdding: .day, value: -6,
                                       to: cal.startOfDay(for: Date())) else { return }
        let interval = DateComponents(day: 1)
        let query = HKStatisticsCollectionQuery(
            quantityType: stepType,
            quantitySamplePredicate: nil,
            options: .cumulativeSum,
            anchorDate: weekStart,
            intervalComponents: interval
        )
        query.initialResultsHandler = { [weak self] _, result, _ in
            var data: [(Date, Int)] = []
            result?.enumerateStatistics(from: weekStart, to: Date()) { stats, _ in
                let count = Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                data.append((stats.startDate, count))
            }
            DispatchQueue.main.async {
                self?.weekSteps = data.map { (date: $0.0, count: $0.1) }
            }
        }
        store.execute(query)
    }

    // MARK: - Sleep

    func fetchSleep() {
        guard let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return }
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        store.execute(HKSampleQuery(sampleType: sleepType, predicate: pred,
                                    limit: 300, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            guard let samples = samples as? [HKCategorySample] else { return }
            let asleepSet: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            ]
            let asleep = samples.filter { asleepSet.contains($0.value) }
            var sessions: [SleepRecord] = []
            var i = 0
            while i < asleep.count {
                var s = asleep[i].startDate
                var e = asleep[i].endDate
                var j = i + 1
                while j < asleep.count,
                      asleep[j].startDate.timeIntervalSince(e) < 3600 {
                    e = max(e, asleep[j].endDate)
                    j += 1
                }
                if e.timeIntervalSince(s) > 3600 {
                    sessions.append(SleepRecord(start: s, end: e))
                }
                i = j
            }
            let sorted = sessions.sorted { $0.start > $1.start }
            DispatchQueue.main.async {
                self?.recentSleep = Array(sorted.prefix(7))
                self?.lastSleep   = sorted.first
            }
        })
    }

    // MARK: - Heart Rate & Calories

    func fetchHeartRate() {
        guard let start = Calendar.current.date(byAdding: .hour, value: -2, to: Date()) else { return }
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        store.execute(HKSampleQuery(sampleType: hrType, predicate: pred,
                                    limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            guard let s = samples?.first as? HKQuantitySample else { return }
            DispatchQueue.main.async {
                self?.heartRate = s.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }
        })
    }

    func fetchCalories() {
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        store.execute(HKStatisticsQuery(quantityType: calType,
                                        quantitySamplePredicate: pred,
                                        options: .cumulativeSum) { [weak self] _, result, _ in
            DispatchQueue.main.async {
                self?.activeCalories = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            }
        })
    }

    // MARK: - Write

    func writeSteps(_ steps: Int, at date: Date = Date()) {
        let qty    = HKQuantity(unit: .count(), doubleValue: Double(steps))
        let sample = HKQuantitySample(type: stepType, quantity: qty, start: date, end: date)
        store.save(sample) { _, _ in }
    }

    func writeSleep(start: Date, end: Date) {
        let sample = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            start: start, end: end
        )
        store.save(sample) { _, _ in }
    }
}
