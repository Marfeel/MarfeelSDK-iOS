//
//  Cdp.swift
//  CompassSDK
//
//  Public CDP facade + singleton.
//
//  The CDP is gated behind two independent conditions: the `enableCdp` opt-in (set at
//  CompassTracker.initialize) AND personalization consent. When either is missing the
//  whole subsystem is inert and no network calls are made.
//

import Foundation

public protocol CdpTracking: AnyObject {
    /// Link a known identifier (login, CRM id, email hash…).
    func cdpDoIdentityLink(type: String, value: String, isDeterministic: Bool)
    /// CDP contribution to the beacon: `{ masterId, rfv, cohorts }`.
    func getCdpData() -> CdpData
    /// Current master_id (nil if unresolved).
    func getCdpMasterId() -> String?

    func addCdpSegment(_ segment: String)
    func removeCdpSegment(_ segment: String)
    func setCdpSegments(_ segments: [String])
    func clearCdpSegments()
    func getCdpSegments() -> [String]

    /// Fetch all meters (stale-while-revalidate). The completion runs off the main thread.
    func getMeterSnapshot(completion: @escaping ([MeterState]) -> Void)
    /// Read the in-memory meter mirror.
    func getMeter(_ name: String) -> MeterState?
    func listMeters() -> [MeterState]
    /// Increment a meter. `.failure(MeterNotFoundError)` when the meter is not configured.
    func incrementMeter(_ name: String, completion: @escaping (Result<MeterState?, Error>) -> Void)
}

public extension CdpTracking {
    func cdpDoIdentityLink(type: String, value: String) {
        cdpDoIdentityLink(type: type, value: value, isDeterministic: false)
    }
}

public enum Cdp {
    public static var shared: CdpTracking { CdpTracker.shared }
}

internal final class CdpTracker: CdpTracking {
    static let shared = CdpTracker()

    private let manager: CdpManager
    private let meteredCounter: MeteredCounter

    init(
        api: CdpApiClient = CdpApiClient(),
        defaults: UserDefaults = UserDefaults(suiteName: CDP_MIRROR_SUITE_NAME) ?? .standard,
        host: CdpHost = CompassTracker.shared
    ) {
        let manager = CdpManager(api: api, host: host, segmentsStore: CdpSegmentsStore(defaults: defaults))
        self.manager = manager
        self.meteredCounter = MeteredCounter(cdpManager: manager, metersStore: CdpMetersStore(defaults: defaults), api: api)

        manager.onMasterIdChanged = { [weak self] _, _ in self?.meteredCounter.reset() }
        registerIdentityResolvedWork(host: host)
    }

    /// Once-per-visit work, fired when identity first becomes available under consent.
    /// Unlike the Android port this is wired internally (the SDK already knows where to
    /// read user-vars and the timezone), so `initialize` doesn't pass it in.
    private func registerIdentityResolvedWork(host: CdpHost) {
        manager.onIdentityResolved { [weak self] in
            guard let self = self else { return }
            self.manager.reconcileSegments()
            var properties = host.cdpUserVars
            properties["timezone"] = TimeZone.current.identifier
            self.manager.updateProfile(properties)
            self.meteredCounter.seed()
            self.meteredCounter.cleanupExpiredMeters(
                account: self.manager.currentAccountIdString(),
                activeMid: self.manager.currentMasterId()
            )
        }
    }

    // MARK: - Public surface

    func cdpDoIdentityLink(type: String, value: String, isDeterministic: Bool) {
        manager.linkIdentity(type: type, value: value, isDeterministic: isDeterministic)
    }

    func getCdpData() -> CdpData { manager.getData() }

    func getCdpMasterId() -> String? { manager.currentMasterId() }

    func addCdpSegment(_ segment: String) { manager.addSegment(segment) }
    func removeCdpSegment(_ segment: String) { manager.removeSegment(segment) }
    func setCdpSegments(_ segments: [String]) { manager.replaceSegments(segments) }
    func clearCdpSegments() { manager.clearSegments() }
    func getCdpSegments() -> [String] { manager.getCdpSegments() }

    func getMeterSnapshot(completion: @escaping ([MeterState]) -> Void) { meteredCounter.getMeterSnapshot(completion: completion) }
    func getMeter(_ name: String) -> MeterState? { meteredCounter.get(name) }
    func listMeters() -> [MeterState] { meteredCounter.list() }
    func incrementMeter(_ name: String, completion: @escaping (Result<MeterState?, Error>) -> Void) { meteredCounter.increment(name: name, completion: completion) }

    // MARK: - Internal hooks (driven by CompassTracker)

    /// Cold-start / enable entry point: resolve identity right away.
    func start() {
        meteredCounter.invalidate()
        manager.resolveIdentity()
    }

    func onNewPage() {
        meteredCounter.invalidate()
        manager.resolveIdentity()
    }

    func onConsentChanged() {
        manager.onConsentChanged()
    }

    func onSiteUserId(_ userId: String) {
        manager.linkIdentity(type: "registered_user_id", value: userId, isDeterministic: true)
    }
}
