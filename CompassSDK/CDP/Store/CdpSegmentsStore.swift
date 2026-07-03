//
//  CdpSegmentsStore.swift
//  CompassSDK
//
//  Per-(account, master_id) segment store. Mirrors CdpSegmentsStore.kt.
//

import Foundation

internal final class CdpSegmentsStore {
    private let store: CdpMirrorStore<[String]>

    init(defaults: UserDefaults, clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        store = CdpMirrorStore<[String]>(
            defaults: defaults,
            prefix: "cdpsegs_",
            payloadKey: "segments",
            serialize: { $0 },
            deserialize: { ($0 as? [String]) ?? [] },
            defaultValue: [],
            clock: clock
        )
    }

    func read(account: String?, masterId: String?) -> [String] { store.read(account: account, masterId: masterId) }
    func write(account: String?, masterId: String?, value: [String]) { store.write(account: account, masterId: masterId, value: value) }
    func clear(account: String?, masterId: String?) { store.clear(account: account, masterId: masterId) }
    func getActiveMid(account: String?) -> String? { store.getActiveMid(account: account) }
    func setActiveMid(account: String?, masterId: String?) { store.setActiveMid(account: account, masterId: masterId) }
    func cleanupExpired(account: String?, activeMidOverride: String? = nil) { store.cleanupExpired(account: account, activeMidOverride: activeMidOverride) }
}
