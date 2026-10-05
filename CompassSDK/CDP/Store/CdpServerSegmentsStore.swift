//
//  CdpServerSegmentsStore.swift
//  CompassSDK
//
//  Mirror of the Server Segments (asserted by the CDP, never by this device) for a
//  `(account, masterId)`. Kept apart from `CdpSegmentsStore` so the device never
//  re-asserts — or removes — a membership it did not claim.
//
//  A cache **miss reads as nil**, distinct from an empty list: the resolve guard in
//  `CdpManager` skips the network only when the mirror has an entry, even an empty one.
//  Keeps no active-mid pointer of its own — callers pass the active master to
//  `cleanupExpired` so it is never purged.
//

import Foundation

internal final class CdpServerSegmentsStore {
    private let store: CdpMirrorStore<[String]?>

    init(defaults: UserDefaults, clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        store = CdpMirrorStore<[String]?>(
            defaults: defaults,
            prefix: "cdpsrvsegs_",
            payloadKey: "segments",
            serialize: { $0 ?? [] },
            deserialize: { ($0 as? [String]) ?? [] },
            defaultValue: nil,
            clock: clock
        )
    }

    func read(account: String?, masterId: String?) -> [String]? { store.read(account: account, masterId: masterId) }
    func write(account: String?, masterId: String?, value: [String]) { store.write(account: account, masterId: masterId, value: value) }
    func clear(account: String?, masterId: String?) { store.clear(account: account, masterId: masterId) }
    func cleanupExpired(account: String?, activeMasterId: String?) { store.cleanupExpired(account: account, activeMidOverride: activeMasterId) }
}
