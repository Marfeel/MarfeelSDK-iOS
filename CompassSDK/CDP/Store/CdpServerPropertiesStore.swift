//
//  CdpServerPropertiesStore.swift
//  CompassSDK
//
//  Mirror of the Server Properties (profile attributes the CDP computes; the device
//  never authors them) for a `(account, masterId)`. Values are coerced to strings on
//  the way in. A cache **miss reads as nil**, distinct from an empty map.
//

import Foundation

internal final class CdpServerPropertiesStore {
    private let store: CdpMirrorStore<[String: String]?>

    init(defaults: UserDefaults, clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        store = CdpMirrorStore<[String: String]?>(
            defaults: defaults,
            prefix: "cdpsrvprops_",
            payloadKey: "properties",
            serialize: { $0 ?? [:] },
            deserialize: { ($0 as? [String: Any]).map { cdpStringValues($0) } ?? [:] },
            defaultValue: nil,
            clock: clock
        )
    }

    func read(account: String?, masterId: String?) -> [String: String]? { store.read(account: account, masterId: masterId) }
    func write(account: String?, masterId: String?, value: [String: String]) { store.write(account: account, masterId: masterId, value: value) }
    func clear(account: String?, masterId: String?) { store.clear(account: account, masterId: masterId) }
    func cleanupExpired(account: String?, activeMasterId: String?) { store.cleanupExpired(account: account, activeMidOverride: activeMasterId) }
}
