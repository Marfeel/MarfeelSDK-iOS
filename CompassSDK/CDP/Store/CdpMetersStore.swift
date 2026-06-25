//
//  CdpMetersStore.swift
//  CompassSDK
//
//  Per-(account, master_id) meter snapshot store (dates serialized to ISO strings).
//  Mirrors CdpMetersStore.kt.
//

import Foundation

internal final class CdpMetersStore {
    private let store: CdpMirrorStore<[MeterState]>

    init(defaults: UserDefaults, clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        store = CdpMirrorStore<[MeterState]>(
            defaults: defaults,
            prefix: "cdpmeters_",
            payloadKey: "meters",
            serialize: { meters in meters.map { $0.toJson() } },
            deserialize: { payload in
                (payload as? [[String: Any]])?.map { MeterState.from(json: $0) } ?? []
            },
            defaultValue: [],
            clock: clock
        )
    }

    func read(account: String?, masterId: String?) -> [MeterState] { store.read(account: account, masterId: masterId) }
    func write(account: String?, masterId: String?, value: [MeterState]) { store.write(account: account, masterId: masterId, value: value) }
    func clear(account: String?, masterId: String?) { store.clear(account: account, masterId: masterId) }
    func getActiveMid(account: String?) -> String? { store.getActiveMid(account: account) }
    func setActiveMid(account: String?, masterId: String?) { store.setActiveMid(account: account, masterId: masterId) }
    func cleanupExpired(account: String?, activeMidOverride: String? = nil) { store.cleanupExpired(account: account, activeMidOverride: activeMidOverride) }
}
