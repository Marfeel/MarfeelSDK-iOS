import Foundation

internal class FrequencyCapManager {
    private static let storageKey = "CompassExperiencesFreqCaps"

    private let defaults: UserDefaults
    private let clock: () -> Int64
    private let timeZone: TimeZone
    private let queue = DispatchQueue(label: "com.marfeel.frequencycaps", attributes: .concurrent)
    private var _lastConfig: [String: [String]] = [:]

    init(
        defaults: UserDefaults = .standard,
        clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        timeZone: TimeZone = .current
    ) {
        self.defaults = defaults
        self.clock = clock
        self.timeZone = timeZone
    }

    private struct EventCounter: Codable {
        var impression: Int64 = 0
        var close: Int64 = 0

        mutating func add(_ other: EventCounter) {
            impression += other.impression
            close += other.close
        }
    }

    private struct ExperienceCounter: Codable {
        var total: EventCounter = EventCounter()
        var last: EventCounter = EventCounter()
        var buckets: [Int: [Int: [Int: EventCounter]]] = [:]
    }

    func trackImpression(experienceId: String) {
        bump(experienceId) { leaf, entry, now in
            leaf.impression += 1
            entry.total.impression += 1
            entry.last.impression = now
        }
    }

    func trackClose(experienceId: String) {
        bump(experienceId) { leaf, entry, now in
            leaf.close += 1
            entry.total.close += 1
            entry.last.close = now
        }
    }

    func getCounts(experienceId: String) -> [String: Int] {
        return queue.sync {
            let entry = loadAll()[experienceId] ?? ExperienceCounter()
            let counts = computeCounts(entry)
            var result: [String: Int] = [:]
            for (k, v) in counts { result[k] = Int(v) }
            return result
        }
    }

    func buildUexp() -> String {
        return queue.sync {
            loadAll()
                .compactMap { (id, entry) in encode(id: id, counts: computeCounts(entry)) }
                .joined(separator: ";")
        }
    }

    func applyResponseConfig(_ config: [String: [String]]) {
        queue.sync(flags: .barrier) {
            _lastConfig = config
            if config.isEmpty {
                defaults.removeObject(forKey: FrequencyCapManager.storageKey)
                return
            }
            let all = loadAll().filter { config.keys.contains($0.key) }
            saveAll(all)
        }
    }

    func getConfig() -> [String: [String]] {
        return queue.sync { _lastConfig }
    }

    func clear() {
        queue.sync(flags: .barrier) {
            _lastConfig = [:]
            defaults.removeObject(forKey: FrequencyCapManager.storageKey)
        }
    }

    private func bump(_ id: String, mutate: (inout EventCounter, inout ExperienceCounter, Int64) -> Void) {
        queue.sync(flags: .barrier) {
            guard _lastConfig.keys.contains(id) else { return }
            var all = loadAll()
            var entry = all[id] ?? ExperienceCounter()
            let now = clock()
            var leaf = leafForWrite(entry: &entry, nowMillis: now)
            mutate(&leaf, &entry, now)
            writeLeaf(&entry, nowMillis: now, leaf: leaf)
            all[id] = entry
            saveAll(all)
        }
    }

    private func computeCounts(_ entry: ExperienceCounter) -> [String: Int64] {
        let now = clock()
        let comps = calendarComponents(at: now)
        let year = comps.year
        let month = comps.month
        let day = comps.day

        let today = readLeaf(entry, year: year, month: month, day: day) ?? EventCounter()
        let thisMonth = sumMonth(entry, year: year, month: month)
        let thisWeek = sumWeek(entry, nowMillis: now)

        return [
            "l": entry.total.impression,
            "cl": entry.total.close,
            "m": thisMonth.impression,
            "cm": thisMonth.close,
            "w": thisWeek.impression,
            "cw": thisWeek.close,
            "d": today.impression,
            "cd": today.close,
            "ls": secondsSince(entry.last.impression, now: now),
            "cls": secondsSince(entry.last.close, now: now),
        ]
    }

    private func sumMonth(_ entry: ExperienceCounter, year: Int, month: Int) -> EventCounter {
        var sum = EventCounter()
        if let monthBuckets = entry.buckets[year]?[month] {
            for counter in monthBuckets.values {
                sum.add(counter)
            }
        }
        return sum
    }

    private func sumWeek(_ entry: ExperienceCounter, nowMillis: Int64) -> EventCounter {
        var cal = isoCalendar()
        cal.timeZone = timeZone
        let date = Date(timeIntervalSince1970: Double(nowMillis) / 1000.0)

        let weekday = cal.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        guard let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: date) else {
            return EventCounter()
        }

        var sum = EventCounter()
        for i in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: i, to: monday) else { continue }
            let comps = cal.dateComponents([.year, .month, .day], from: day)
            guard let y = comps.year, let m = comps.month, let d = comps.day else { continue }
            if let leaf = readLeaf(entry, year: y, month: m, day: d) {
                sum.add(leaf)
            }
        }
        return sum
    }

    private func leafForWrite(entry: inout ExperienceCounter, nowMillis: Int64) -> EventCounter {
        let comps = calendarComponents(at: nowMillis)
        return entry.buckets[comps.year]?[comps.month]?[comps.day] ?? EventCounter()
    }

    private func writeLeaf(_ entry: inout ExperienceCounter, nowMillis: Int64, leaf: EventCounter) {
        let comps = calendarComponents(at: nowMillis)
        if entry.buckets[comps.year] == nil { entry.buckets[comps.year] = [:] }
        if entry.buckets[comps.year]![comps.month] == nil { entry.buckets[comps.year]![comps.month] = [:] }
        entry.buckets[comps.year]![comps.month]![comps.day] = leaf
    }

    private func readLeaf(_ entry: ExperienceCounter, year: Int, month: Int, day: Int) -> EventCounter? {
        return entry.buckets[year]?[month]?[day]
    }

    private func secondsSince(_ stamp: Int64, now: Int64) -> Int64 {
        return stamp > 0 ? (now - stamp) / 1000 : 0
    }

    private func encode(id: String, counts: [String: Int64]) -> String? {
        let parts = counts.sorted(by: { $0.key < $1.key })
            .filter { $0.value > 0 }
            .flatMap { [$0.key, String($0.value)] }
        if parts.isEmpty { return nil }
        return "\(id),\(parts.joined(separator: "|"))"
    }

    private struct CalComponents {
        let year: Int
        let month: Int
        let day: Int
    }

    private func calendarComponents(at millis: Int64) -> CalComponents {
        var cal = Calendar.current
        cal.timeZone = timeZone
        let date = Date(timeIntervalSince1970: Double(millis) / 1000.0)
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return CalComponents(year: comps.year!, month: comps.month!, day: comps.day!)
    }

    private func isoCalendar() -> Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = timeZone
        cal.firstWeekday = 2 // Monday
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    private func loadAll() -> [String: ExperienceCounter] {
        guard let data = defaults.data(forKey: FrequencyCapManager.storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: ExperienceCounter].self, from: data)) ?? [:]
    }

    private func saveAll(_ all: [String: ExperienceCounter]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: FrequencyCapManager.storageKey)
    }
}
