//
//  CdpManager.swift
//  CompassSDK
//
//  CDP identity state machine + segments + properties.
//
//  iOS has no coroutines, so the per-session memoization (Android's Deferred/Mutex) is
//  a serial DispatchQueue guarding the resolve state plus a list of pending completions
//  that share a single in-flight network call. The host (CompassTracker) is reached
//  through the `CdpHost` protocol rather than a bag of closures.
//

import Foundation

/// Everything the CDP needs from the surrounding tracker. Keeps the tracker the single
/// owner of persistence, session, consent and account config.
internal protocol CdpHost: AnyObject {
    var cdpEnabled: Bool { get }
    var cdpAccountId: Int? { get }
    var cdpUserId: String { get }
    var cdpSessionId: String { get }
    var cdpConsent: Bool? { get }
    var cdpUserVars: [String: String] { get }
    func cdpReadMasterId() -> String?
    func cdpWriteMasterId(_ id: String) -> String?
    func cdpReadCachedIdentity(sessionId: String) -> CdpCachedIdentity?
    func cdpWriteCachedIdentity(rfv: CdpRfv?, cohorts: [Int], sessionId: String)
}

internal final class CdpManager {
    private let api: CdpApiClient
    private let host: CdpHost
    private let segmentsStore: CdpSegmentsStore

    /// Fired (old, new) whenever the master_id changes. Wired to reset the meter mirror.
    var onMasterIdChanged: ((String?, String) -> Void)?

    private let queue = DispatchQueue(label: "com.marfeel.cdp.manager")

    private enum ResolveState { case idle, inFlight, done }
    private var resolveState: ResolveState = .idle
    private var memoSessionId: String?
    private var pending: [() -> Void] = []

    private var identityResolved = false
    private var oneShotCallback: (() -> Void)?

    init(api: CdpApiClient, host: CdpHost, segmentsStore: CdpSegmentsStore) {
        self.api = api
        self.host = host
        self.segmentsStore = segmentsStore
    }

    // MARK: - Gating & accessors

    /// Consent for the "personalization" purpose: enabled AND consent not explicitly false.
    func hasConsent() -> Bool { host.cdpEnabled && host.cdpConsent != false }

    func currentMasterId() -> String? { host.cdpReadMasterId() }

    func currentAccountIdString() -> String? { host.cdpAccountId.map(String.init) }

    private var storageMid: String { host.cdpReadMasterId() ?? LOCAL_MID_SENTINEL }

    // MARK: - One-shot

    func onIdentityResolved(_ callback: @escaping () -> Void) {
        queue.async {
            self.oneShotCallback = callback
            self.maybeFireOneShotLocked()
        }
    }

    /// MUST be called on `queue`.
    private func maybeFireOneShotLocked() {
        guard !identityResolved else { return }
        if hasConsent() && host.cdpReadMasterId() != nil {
            identityResolved = true
            oneShotCallback?()
        }
    }

    // MARK: - Identity resolution

    func resolveIdentity(completion: (() -> Void)? = nil) {
        guard hasConsent() else { completion?(); return }
        let session = host.cdpSessionId

        queue.async {
            if session != self.memoSessionId {
                self.memoSessionId = session
                self.resolveState = .idle
                self.identityResolved = false
            }

            switch self.resolveState {
            case .done:
                completion?()
            case .inFlight:
                completion.map { self.pending.append($0) }
            case .idle:
                self.resolveState = .inFlight
                completion.map { self.pending.append($0) }
                self.runResolveLocked(session)
            }
        }
    }

    /// MUST be called on `queue`.
    private func runResolveLocked(_ session: String) {
        // Skip the network if we're already resolved (cached identity + master_id).
        guard host.cdpReadCachedIdentity(sessionId: session) == nil || host.cdpReadMasterId() == nil else {
            finishResolveLocked()
            return
        }
        guard let siteId = host.cdpAccountId else {
            finishResolveLocked()
            return
        }

        let params = CdpResolveParams(siteId: siteId, cookieId: host.cdpUserId, masterId: host.cdpReadMasterId())
        api.resolve(params) { [weak self] response in
            self?.queue.async {
                self?.applyStateLocked(response, session: session)
                self?.finishResolveLocked()
            }
        }
    }

    /// MUST be called on `queue`. Marks the resolve done (or idle to retry on failure)
    /// and drains pending completions.
    private func finishResolveLocked() {
        resolveState = host.cdpReadMasterId() != nil ? .done : .idle
        let callbacks = pending
        pending = []
        maybeFireOneShotLocked()
        callbacks.forEach { $0() }
    }

    func linkIdentity(type: String, value: String, isDeterministic: Bool, completion: (() -> Void)? = nil) {
        guard hasConsent() else { completion?(); return }
        resolveIdentity { [weak self] in
            guard let self = self, let siteId = self.host.cdpAccountId else { completion?(); return }
            let params = CdpLinkParams(
                siteId: siteId,
                idType: type,
                idValue: value,
                isDeterministic: isDeterministic,
                masterId: self.host.cdpReadMasterId()
            )
            self.api.link(params) { [weak self] response in
                self?.queue.async {
                    self?.applyStateLocked(response, session: self?.host.cdpSessionId ?? "")
                    completion?()
                }
            }
        }
    }

    func onConsentChanged() {
        resolveIdentity()
        queue.async { self.maybeFireOneShotLocked() }
    }

    /// Single write path for every endpoint response. MUST be called on `queue`.
    private func applyStateLocked(_ response: CdpIdentityResponse, session: String) {
        if let masterId = response.masterId, !masterId.isEmpty {
            let old = host.cdpWriteMasterId(masterId)
            transferCdpSegments(oldId: old, newId: masterId)
            if old != masterId { onMasterIdChanged?(old, masterId) }
        }
        host.cdpWriteCachedIdentity(rfv: response.rfv, cohorts: response.cohorts, sessionId: session)
        maybeFireOneShotLocked()
    }

    // MARK: - Properties

    func updateProfile(_ properties: [String: String], completion: (() -> Void)? = nil) {
        guard hasConsent(), let masterId = host.cdpReadMasterId(), let siteId = host.cdpAccountId, !properties.isEmpty else {
            completion?()
            return
        }
        let params = CdpProfileUpdateParams(siteId: siteId, masterId: masterId, properties: properties)
        api.update(params) { [weak self] response in
            self?.queue.async {
                self?.applyStateLocked(response, session: self?.host.cdpSessionId ?? "")
                completion?()
            }
        }
    }

    // MARK: - Segments

    func getCdpSegments() -> [String] {
        guard host.cdpEnabled else { return [] }
        return segmentsStore.read(account: currentAccountIdString(), masterId: storageMid)
    }

    func addSegment(_ segment: String) {
        mutateSegments { local in local.contains(segment) ? nil : (local + [segment], [segment], nil) }
    }

    func removeSegment(_ segment: String) {
        mutateSegments { local in (local.filter { $0 != segment }, nil, [segment]) }
    }

    func clearSegments() {
        mutateSegments { local in (local: [], add: nil, remove: local.isEmpty ? nil : local) }
    }

    func replaceSegments(_ segments: [String]) {
        mutateSegments { previous in
            let deduped = self.dedup(segments)
            // Diff against the previous LOCAL snapshot, not the backend.
            let adds = deduped.filter { !previous.contains($0) }
            let removes = previous.filter { !deduped.contains($0) }
            return (deduped, adds.isEmpty ? nil : adds, removes.isEmpty ? nil : removes)
        }
    }

    /// Local-first segment mutation: compute the new list + delta from the current local
    /// list, write locally (even pre-consent), then sync the delta. Returning nil from
    /// `transform` is a no-op (e.g. adding a segment that already exists).
    private func mutateSegments(_ transform: @escaping (_ local: [String]) -> (local: [String], add: [String]?, remove: [String]?)?) {
        guard host.cdpEnabled else { return }
        queue.async {
            let account = self.currentAccountIdString()
            let mid = self.storageMid
            let local = self.segmentsStore.read(account: account, masterId: mid)
            guard let result = transform(local) else { return }
            self.segmentsStore.write(account: account, masterId: mid, value: result.local)
            if result.add != nil || result.remove != nil {
                self.postSegmentChangeLocked(segmentsAdd: result.add, segmentsRemove: result.remove)
            }
        }
    }

    /// Flush local segments as adds (idempotent). Pre-consent removes are not recovered.
    func reconcileSegments() {
        guard hasConsent(), let masterId = host.cdpReadMasterId() else { return }
        queue.async {
            let local = self.segmentsStore.read(account: self.currentAccountIdString(), masterId: masterId)
            if !local.isEmpty {
                self.postSegmentChangeLocked(segmentsAdd: local, segmentsRemove: nil)
            }
        }
    }

    /// MUST be called on `queue`.
    private func postSegmentChangeLocked(segmentsAdd: [String]?, segmentsRemove: [String]?) {
        guard hasConsent(), let masterId = host.cdpReadMasterId(), let siteId = host.cdpAccountId else { return }
        let params = CdpProfileUpdateParams(siteId: siteId, masterId: masterId, segmentsAdd: segmentsAdd, segmentsRemove: segmentsRemove)
        api.update(params) { [weak self] response in
            self?.queue.async {
                self?.applyStateLocked(response, session: self?.host.cdpSessionId ?? "")
            }
        }
    }

    /// Carry the previous bucket's segments into the new master_id's bucket.
    /// Best-effort — must never bubble up. MUST be called on `queue`.
    private func transferCdpSegments(oldId: String?, newId: String) {
        guard let account = currentAccountIdString(), !account.isEmpty else { return }
        let previousMid = oldId ?? segmentsStore.getActiveMid(account: account) ?? LOCAL_MID_SENTINEL
        if previousMid == newId {
            segmentsStore.setActiveMid(account: account, masterId: newId)
            return
        }
        let previous = segmentsStore.read(account: account, masterId: previousMid)
        let current = segmentsStore.read(account: account, masterId: newId)
        let union = dedup(current + previous)
        if !union.isEmpty { segmentsStore.write(account: account, masterId: newId, value: union) }
        segmentsStore.clear(account: account, masterId: previousMid)
        segmentsStore.setActiveMid(account: account, masterId: newId)
        segmentsStore.cleanupExpired(account: account, activeMidOverride: newId)
    }

    private func dedup(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    // MARK: - Beacon data

    func getData() -> CdpData {
        guard host.cdpEnabled else { return CdpData(masterId: nil, rfv: nil, cohorts: []) }
        let cached = host.cdpReadCachedIdentity(sessionId: host.cdpSessionId)
        return CdpData(masterId: host.cdpReadMasterId(), rfv: cached?.rfv, cohorts: cached?.cohorts ?? [])
    }
}
