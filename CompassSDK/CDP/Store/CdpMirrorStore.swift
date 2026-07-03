//
//  CdpMirrorStore.swift
//  CompassSDK
//
//  Generic TTL'd per-(account, master_id) key/value store backed by UserDefaults.
//  Mirrors CdpMirrorStore.kt. Used by both segments and meters.
//
//  Envelope shape per data key: { "<payloadKey>": <payload>, "ts": <epoch_ms> }
//

import Foundation

internal final class CdpMirrorStore<T> {
    private let defaults: UserDefaults
    private let prefix: String
    private let payloadKey: String
    private let serialize: (T) -> Any
    private let deserialize: (Any) -> T
    private let defaultValue: T
    private let clock: () -> Int64

    init(
        defaults: UserDefaults,
        prefix: String,
        payloadKey: String,
        serialize: @escaping (T) -> Any,
        deserialize: @escaping (Any) -> T,
        defaultValue: T,
        clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.defaults = defaults
        self.prefix = prefix
        self.payloadKey = payloadKey
        self.serialize = serialize
        self.deserialize = deserialize
        self.defaultValue = defaultValue
        self.clock = clock
    }

    private func dataKey(_ account: String, _ masterId: String) -> String { "\(prefix)\(masterId)_\(account)" }
    private func indexKey(_ account: String) -> String { "\(prefix)index_\(account)" }
    private func activeMidKey(_ account: String) -> String { "\(prefix)active_mid_\(account)" }

    func read(account: String?, masterId: String?) -> T {
        guard let account = account, !account.isEmpty,
              let masterId = masterId, !masterId.isEmpty else { return defaultValue }
        guard let envelope = defaults.dictionary(forKey: dataKey(account, masterId)) else { return defaultValue }
        guard let ts = (envelope["ts"] as? NSNumber)?.int64Value else { return defaultValue }
        if clock() - ts >= CDP_MIRROR_TTL_MS { return defaultValue }
        guard let payload = envelope[payloadKey] else { return defaultValue }
        return deserialize(payload)
    }

    func write(account: String?, masterId: String?, value: T) {
        guard let account = account, !account.isEmpty,
              let masterId = masterId, !masterId.isEmpty else { return }
        let envelope: [String: Any] = [
            payloadKey: serialize(value),
            "ts": NSNumber(value: clock())
        ]
        defaults.set(envelope, forKey: dataKey(account, masterId))
        addToIndex(account: account, masterId: masterId)
    }

    func clear(account: String?, masterId: String?) {
        guard let account = account, !account.isEmpty,
              let masterId = masterId, !masterId.isEmpty else { return }
        defaults.removeObject(forKey: dataKey(account, masterId))
        var index = readIndex(account)
        if let idx = index.firstIndex(of: masterId) {
            index.remove(at: idx)
            writeIndex(account, index)
        }
    }

    func getActiveMid(account: String?) -> String? {
        guard let account = account, !account.isEmpty else { return nil }
        return defaults.string(forKey: activeMidKey(account))
    }

    func setActiveMid(account: String?, masterId: String?) {
        guard let account = account, !account.isEmpty,
              let masterId = masterId, !masterId.isEmpty else { return }
        defaults.set(masterId, forKey: activeMidKey(account))
    }

    func cleanupExpired(account: String?, activeMidOverride: String? = nil) {
        guard let account = account, !account.isEmpty else { return }
        let active = activeMidOverride ?? getActiveMid(account: account)
        let index = readIndex(account)
        let survivors = index.filter { $0 == active || isFresh(account: account, masterId: $0) }
        if survivors.count == index.count { return }

        index.filter { !survivors.contains($0) }.forEach {
            defaults.removeObject(forKey: dataKey(account, $0))
        }
        writeIndex(account, survivors)
    }

    private func isFresh(account: String, masterId: String) -> Bool {
        guard let envelope = defaults.dictionary(forKey: dataKey(account, masterId)),
              let ts = (envelope["ts"] as? NSNumber)?.int64Value else { return false }
        return clock() - ts < CDP_MIRROR_TTL_MS
    }

    private func readIndex(_ account: String) -> [String] {
        return defaults.array(forKey: indexKey(account)) as? [String] ?? []
    }

    private func writeIndex(_ account: String, _ index: [String]) {
        defaults.set(index, forKey: indexKey(account))
    }

    private func addToIndex(account: String, masterId: String) {
        var index = readIndex(account)
        if !index.contains(masterId) {
            index.append(masterId)
            writeIndex(account, index)
        }
    }
}
