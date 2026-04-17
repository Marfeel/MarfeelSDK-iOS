import Foundation

internal class ReadEditorialsManager {
    private static let storageKey = "CompassReadEditorials"
    private static let maxEntries = 100
    private static let ttlSeconds: Int64 = 30 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let clock: () -> Int64
    private let queue = DispatchQueue(label: "com.marfeel.readeditorials", attributes: .concurrent)

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }) {
        self.defaults = defaults
        self.clock = clock
    }

    private struct Entry: Codable {
        let id: String
        let ts: Int64
    }

    func add(_ editorialId: String) {
        let trimmed = editorialId.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return }

        queue.sync(flags: .barrier) {
            let now = clock()
            var entries = readEntries().filter { $0.id != trimmed }
            entries.append(Entry(id: trimmed, ts: now))
            writeEntries(prune(entries, now: now))
        }
    }

    func getIds() -> [String] {
        return queue.sync {
            let now = clock()
            return prune(readEntries(), now: now).map { $0.id }
        }
    }

    func buildRedParam() -> String {
        let ids = getIds().compactMap { Int64($0) }.sorted()
        if ids.isEmpty { return "" }

        var parts: [String] = []
        var previous: Int64 = 0
        for id in ids {
            parts.append(String(id - previous))
            previous = id
        }
        return parts.joined(separator: ",")
    }

    func clear() {
        queue.sync(flags: .barrier) {
            defaults.removeObject(forKey: ReadEditorialsManager.storageKey)
        }
    }

    private func prune(_ entries: [Entry], now: Int64) -> [Entry] {
        let fresh = entries.filter { now - $0.ts < ReadEditorialsManager.ttlSeconds }
        if fresh.count <= ReadEditorialsManager.maxEntries { return fresh }
        return Array(fresh.suffix(ReadEditorialsManager.maxEntries))
    }

    private func readEntries() -> [Entry] {
        guard let data = defaults.data(forKey: ReadEditorialsManager.storageKey) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func writeEntries(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: ReadEditorialsManager.storageKey)
    }
}
