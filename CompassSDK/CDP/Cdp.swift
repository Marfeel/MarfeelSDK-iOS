//
//  Cdp.swift
//  CompassSDK
//
//  Public CDP facade + singleton.
//
//  This protocol is the iOS counterpart of the web `compass.cdp` namespace and is treated
//  as **add-only**: names are never renamed or removed once shipped (a test pins them).
//  Superseded names stay as deprecated delegates.
//
//  Everything here is inert — no network, `nil` / `false` / empty answers — unless the
//  SDK was initialized with `enableCdp: true`. Identity calls are additionally gated on
//  personalization consent (`CompassTracking.setConsent`); the publisher-consent calls
//  (`trackConsent`, `getConsent`, `hasConsent`) deliberately are **not**.
//
//  Completions run off the main thread.
//

import Foundation

public protocol CdpTracking: AnyObject {
    // MARK: Identity

    /// Link an external identifier to the current visitor and adopt the master the CDP
    /// resolves it to. `completion` fires once the link round-trip completes (or is
    /// skipped for lack of consent). See `CdpIdentityTypes` for the well-known types.
    /// `isDeterministic` forces a device-bound type to make the user registered.
    func setIdentity(type: String, value: String, isDeterministic: Bool, completion: (() -> Void)?)

    /// Unlink an identity from the current master. With a nil `value`, every identity of
    /// `type` the master owns is unlinked. An empty `type` names nothing to delete and is
    /// a no-op (asserts in debug). No-op without a master or consent.
    func deleteIdentity(type: String, value: String?, completion: (() -> Void)?)

    /// The current CDP master_id, or nil before the first resolve / without consent.
    func getMasterId() -> String?

    /// The CDP's contribution to a beacon: master_id, read-only rfv/cohorts and whether
    /// this process resolved the identity itself.
    func getUserProfile() -> CdpData

    @available(*, deprecated, renamed: "setIdentity(type:value:isDeterministic:)")
    func cdpDoIdentityLink(type: String, value: String, isDeterministic: Bool)
    @available(*, deprecated, renamed: "getUserProfile()")
    func getCdpData() -> CdpData
    @available(*, deprecated, renamed: "getMasterId()")
    func getCdpMasterId() -> String?

    // MARK: Identity types & hashing

    /// `trim` + lower-case, the server's rule.
    func normalizeEmail(_ email: String) -> String
    /// `trim` only — never case-folded; `+34600111222` and `600111222` stay two users.
    func normalizePhone(_ phone: String) -> String
    /// SHA-256 hex of `normalizeEmail`; send under `CdpIdentityTypes.emailSha256`.
    func hashEmail(_ email: String) -> String
    /// SHA-256 hex of `normalizePhone`; send under `CdpIdentityTypes.phoneSha256`.
    func hashPhone(_ phone: String) -> String

    // MARK: Publisher consents

    /// Record that the visitor accepted or rejected a publisher consent. Not gated on
    /// personalization consent. Recorded under the current master when one exists; an
    /// anonymous decision is remembered locally and replayed once a master exists.
    /// nil on failure or when CDP is disabled.
    func trackConsent(_ decision: CdpConsent, completion: @escaping (CdpConsentRecordResponse?) -> Void)
    /// Read a consent's definition from the catalog. nil when unknown, on failure, or when CDP is disabled.
    func getConsent(_ ref: CdpConsentRef, completion: @escaping (CdpConsentDefinition?) -> Void)
    /// Whether the visitor has **accepted** the consent (at exactly `versionId` when given).
    /// False — never nil — on failure and when CDP is disabled. Answered from local memory
    /// when the device has neither a master nor an email to ask with.
    func hasConsent(_ query: CdpConsentQuery, completion: @escaping (Bool) -> Void)

    // MARK: Segments & properties

    func addCdpSegment(_ segment: String)
    func removeCdpSegment(_ segment: String)
    func setCdpSegments(_ segments: [String])
    func clearCdpSegments()
    /// Synchronous read of the local CDP segment mirror for the current identity.
    func getCdpSegments() -> [String]

    /// Server Segments (asserted by the CDP, not by this device) known right now, without resolving.
    func listServerSegments() -> [String]
    /// Server Segments after an identity resolve.
    func getServerSegments(completion: @escaping ([String]) -> Void)
    /// Server Properties (computed by the CDP) known right now, without resolving.
    func listServerProperties() -> [String: String]
    /// Server Properties after an identity resolve.
    func getServerProperties(completion: @escaping ([String: String]) -> Void)

    // MARK: Meters

    /// Fetch all meters (stale-while-revalidate). The completion runs off the main thread.
    func getMeterSnapshot(completion: @escaping ([MeterState]) -> Void)
    /// Read the in-memory meter mirror.
    func getMeter(_ name: String) -> MeterState?
    func listMeters() -> [MeterState]
    /// Increment a meter. `.failure(MeterNotFoundError)` when the meter is not configured.
    func incrementMeter(_ name: String, completion: @escaping (Result<MeterState?, Error>) -> Void)
}

public extension CdpTracking {
    func setIdentity(type: String, value: String, isDeterministic: Bool = false) {
        setIdentity(type: type, value: value, isDeterministic: isDeterministic, completion: nil)
    }

    func deleteIdentity(type: String, value: String? = nil) {
        deleteIdentity(type: type, value: value, completion: nil)
    }

    @available(*, deprecated, renamed: "setIdentity(type:value:)")
    func cdpDoIdentityLink(type: String, value: String) {
        cdpDoIdentityLink(type: type, value: value, isDeterministic: false)
    }

    /// The well-known identity types; see `CdpIdentityTypes`.
    var identityTypes: CdpIdentityTypes.Type { CdpIdentityTypes.self }
}

public enum Cdp {
    public static var shared: CdpTracking { CdpTracker.shared }
}

internal final class CdpTracker: CdpTracking {
    static let shared = CdpTracker()

    /// Internal for tests; hosts reach the CDP through the protocol only.
    let manager: CdpManager
    private let meteredCounter: MeteredCounter
    private let metersStore: CdpMetersStore

    private let flushQueue = DispatchQueue(label: "com.marfeel.cdp.uservars.flush")
    private var flushWorkItem: DispatchWorkItem?
    private static let userVarsFlushDebounce: TimeInterval = 0.05

    init(
        api: CdpApiClient = CdpApiClient(),
        defaults: UserDefaults = UserDefaults(suiteName: CDP_MIRROR_SUITE_NAME) ?? .standard,
        host: CdpHost = CompassTracker.shared
    ) {
        let metersStore = CdpMetersStore(defaults: defaults)
        let manager = CdpManager(
            api: api,
            host: host,
            segmentsStore: CdpSegmentsStore(defaults: defaults),
            serverSegmentsStore: CdpServerSegmentsStore(defaults: defaults),
            serverPropertiesStore: CdpServerPropertiesStore(defaults: defaults),
            consentMemory: CdpConsentMemoryStore(defaults: defaults)
        )
        self.manager = manager
        self.metersStore = metersStore
        self.meteredCounter = MeteredCounter(cdpManager: manager, metersStore: metersStore, api: api)

        manager.onMasterIdChanged = { [weak self] _, _ in self?.meteredCounter.reset() }
        // A user reset wipes the meters too: the in-memory mirror and the bucket of the previous master.
        manager.onIdentityCleared = { [weak self] account, previousMid in
            self?.meteredCounter.reset()
            self?.metersStore.clear(account: account, masterId: previousMid)
        }
        registerIdentityResolvedWork(host: host)
    }

    /// Once-per-visit work, fired when identity first becomes available under consent:
    /// bridge legacy segments, reconcile, push the owned user vars + timezone, seed the
    /// meters, and replay the consent decisions recorded while anonymous.
    private func registerIdentityResolvedWork(host: CdpHost) {
        manager.onIdentityResolved { [weak self] in
            guard let self = self else { return }
            self.manager.mergeLegacySegments()
            self.manager.reconcileSegments()
            var properties = host.cdpUserVars
            properties["timezone"] = TimeZone.current.identifier
            self.manager.updateProfile(properties)
            self.meteredCounter.seed()
            self.meteredCounter.cleanupExpiredMeters(
                account: self.manager.currentAccountIdString(),
                activeMid: self.manager.currentMasterId()
            )
            self.manager.replayConsentDecisions()
        }
    }

    // MARK: - Identity

    /// An empty value is rejected rather than posted: the request would fail, be swallowed
    /// into `UNKNOWN_CDP_IDENTITY`, and its empty rfv/cohorts cached over the real ones.
    func setIdentity(type: String, value: String, isDeterministic: Bool, completion: (() -> Void)?) {
        guard !type.isEmpty, !value.isEmpty else {
            assertionFailure("Cdp.setIdentity: type and value are required")
            deliverOffStack(completion)
            return
        }
        manager.linkIdentity(type: type, value: value, isDeterministic: isDeterministic, completion: completion)
    }

    func deleteIdentity(type: String, value: String?, completion: (() -> Void)?) {
        guard !type.isEmpty else {
            assertionFailure("Cdp.deleteIdentity: type is required")
            deliverOffStack(completion)
            return
        }
        manager.deleteIdentity(type: type, value: value, completion: completion)
    }

    /// Every completion of this facade runs off the caller's stack, even when gated.
    private func deliverOffStack(_ completion: (() -> Void)?) {
        guard let completion = completion else { return }
        DispatchQueue.global(qos: .utility).async(execute: completion)
    }

    func getMasterId() -> String? { manager.currentMasterId() }

    func getUserProfile() -> CdpData { manager.getUserProfile() }

    func cdpDoIdentityLink(type: String, value: String, isDeterministic: Bool) {
        manager.linkIdentity(type: type, value: value, isDeterministic: isDeterministic)
    }

    func getCdpData() -> CdpData { getUserProfile() }

    func getCdpMasterId() -> String? { getMasterId() }

    // MARK: - Hashing

    func normalizeEmail(_ email: String) -> String { CdpHash.normalizeEmail(email) }
    func normalizePhone(_ phone: String) -> String { CdpHash.normalizePhone(phone) }
    func hashEmail(_ email: String) -> String { CdpHash.hashEmail(email) }
    func hashPhone(_ phone: String) -> String { CdpHash.hashPhone(phone) }

    // MARK: - Publisher consents

    /// Best-effort resolve first, so a consented visitor records under a master.
    func trackConsent(_ decision: CdpConsent, completion: @escaping (CdpConsentRecordResponse?) -> Void) {
        manager.resolveIdentity { [weak self] in
            guard let self = self else { completion(nil); return }
            self.manager.trackCdpConsent(decision, completion: completion)
        }
    }

    /// Test seam: waits until everything already queued on the manager has run.
    func drainForTesting() { manager.drainQueueForTesting() }

    /// A pure catalog read — no identity resolve.
    func getConsent(_ ref: CdpConsentRef, completion: @escaping (CdpConsentDefinition?) -> Void) {
        manager.getCdpConsent(ref, completion: completion)
    }

    /// Resolves first, so a returning visitor with no cached master gets a subject.
    func hasConsent(_ query: CdpConsentQuery, completion: @escaping (Bool) -> Void) {
        manager.resolveIdentity { [weak self] in
            guard let self = self else { completion(false); return }
            self.manager.hasCdpConsent(query, completion: completion)
        }
    }

    // MARK: - Segments & properties

    func addCdpSegment(_ segment: String) { manager.addSegment(segment) }
    func removeCdpSegment(_ segment: String) { manager.removeSegment(segment) }
    func setCdpSegments(_ segments: [String]) { manager.replaceSegments(segments) }
    func clearCdpSegments() { manager.clearSegments() }
    func getCdpSegments() -> [String] { manager.getCdpSegments() }

    func listServerSegments() -> [String] { manager.serverSegments }
    func getServerSegments(completion: @escaping ([String]) -> Void) { manager.getServerSegments(completion: completion) }
    func listServerProperties() -> [String: String] { manager.serverProperties }
    func getServerProperties(completion: @escaping ([String: String]) -> Void) { manager.getServerProperties(completion: completion) }

    // MARK: - Meters

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
        manager.linkIdentity(type: CdpIdentityTypes.registeredUserId, value: userId, isDeterministic: true)
    }

    /// Push the device-owned user vars to the CDP profile, debounced so a burst of
    /// `setUserVar` calls lands as one `/update/`. Only owned vars travel — Server
    /// Properties are never echoed back.
    func flushUserVars(_ ownedUserVars: @escaping () -> [String: String]) {
        flushQueue.async {
            self.flushWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.manager.updateProfile(ownedUserVars()) }
            self.flushWorkItem = item
            self.flushQueue.asyncAfter(deadline: .now() + CdpTracker.userVarsFlushDebounce, execute: item)
        }
    }

    /// The synchronous local CDP wipe behind `resetUser()`: master_id, cached rfv/cohorts
    /// (as absent), resolve memo, freshness, Server Segment / Property mirrors, meters,
    /// per-master storage, anonymous consent memory and the active-mid pointer.
    func clearIdentity() {
        manager.clearIdentity()
    }

    /// The best-effort remote tail of `resetUser()`; nil on failure, inert when disabled.
    func resetRemoteIdentity(completion: @escaping (CdpResetResponse?) -> Void) {
        manager.resetRemoteIdentity(completion: completion)
    }
}
