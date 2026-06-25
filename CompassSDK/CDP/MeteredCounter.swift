//
//  MeteredCounter.swift
//  CompassSDK
//
//  Stale-while-revalidate meter mirror + increment. Mirrors MeteredCounter.kt.
//

import Foundation

internal final class MeteredCounter {
    private let cdpManager: CdpManager
    private let metersStore: CdpMetersStore
    private let api: CdpApiClient

    private let queue = DispatchQueue(label: "com.marfeel.cdp.meters")

    private var meters: [MeterState] = []
    private var fresh = false
    private var seeded = false
    private var inflight = false
    private var inflightPending: [([MeterState]) -> Void] = []

    init(cdpManager: CdpManager, metersStore: CdpMetersStore, api: CdpApiClient) {
        self.cdpManager = cdpManager
        self.metersStore = metersStore
        self.api = api
    }

    private func ready() -> Bool { cdpManager.hasConsent() && cdpManager.currentMasterId() != nil }

    // MARK: - Seeding (sync read from persistence)

    func seed() {
        guard ready() else { return }
        queue.sync {
            guard !seeded else { return }
            runSeedLocked()
            seeded = true
        }
    }

    /// MUST be called on `queue`. Never overwrites an already-populated mirror.
    private func runSeedLocked() {
        guard meters.isEmpty else { return }
        let stored = metersStore.read(account: cdpManager.currentAccountIdString(), masterId: cdpManager.currentMasterId())
        if meters.isEmpty && !stored.isEmpty { meters = stored }
    }

    // MARK: - Snapshot (SWR)

    func getMeterSnapshot(completion: @escaping ([MeterState]) -> Void) {
        guard ready() else {
            completion(queue.sync { meters })
            return
        }
        queue.async {
            if !self.seeded { self.runSeedLocked(); self.seeded = true }
            if self.fresh {
                completion(self.meters)
                return
            }
            self.inflightPending.append(completion)
            if self.inflight { return }
            self.inflight = true

            guard let account = self.cdpManager.currentAccountIdString(),
                  let masterId = self.cdpManager.currentMasterId() else {
                self.finishFetchLocked(nil)
                return
            }
            self.api.fetchMeters(siteId: account, masterId: masterId) { [weak self] fetched in
                self?.queue.async { self?.finishFetchLocked(fetched) }
            }
        }
    }

    /// MUST be called on `queue`.
    private func finishFetchLocked(_ fetched: [MeterState]?) {
        if let fetched = fetched {
            meters = fetched
            fresh = true
            persistLocked(fetched)
        }
        // Fail-open: a failed fetch keeps the last-good mirror and stays not-fresh.
        let pending = inflightPending
        inflightPending = []
        inflight = false
        pending.forEach { $0(meters) }
    }

    // MARK: - Sync reads

    func get(_ name: String) -> MeterState? { queue.sync { meters.first { $0.name == name } } }

    func list() -> [MeterState] { queue.sync { meters } }

    func invalidate() { queue.async { self.fresh = false } }

    func reset() {
        queue.async {
            self.meters = []
            self.fresh = false
            self.seeded = false
            self.inflight = false
            self.inflightPending = []
        }
    }

    func cleanupExpiredMeters(account: String?, activeMid: String?) {
        metersStore.cleanupExpired(account: account, activeMidOverride: activeMid)
    }

    // MARK: - Increment

    func increment(name: String, completion: @escaping (Result<MeterState?, Error>) -> Void) {
        guard ready(),
              let account = cdpManager.currentAccountIdString(),
              let masterId = cdpManager.currentMasterId() else {
            completion(.success(nil))
            return
        }
        api.incrementMeter(name: name, siteId: account, masterId: masterId) { [weak self] result in
            guard let self = self else { completion(.success(nil)); return }
            self.queue.async {
                if result.status == 404 {
                    completion(.failure(MeterNotFoundError(meterName: name)))
                    return
                }
                guard let state = result.state else {
                    completion(.success(self.meters.first { $0.name == name }))
                    return
                }
                if self.meters.contains(where: { $0.name == name }) {
                    self.meters = self.meters.map { $0.name == name ? state : $0 }
                } else {
                    self.meters = self.meters + [state]
                }
                self.persistLocked(self.meters)
                completion(.success(state))
            }
        }
    }

    /// MUST be called on `queue`.
    private func persistLocked(_ value: [MeterState]) {
        metersStore.write(account: cdpManager.currentAccountIdString(), masterId: cdpManager.currentMasterId(), value: value)
    }
}
