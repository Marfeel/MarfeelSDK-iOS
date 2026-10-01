//
//  CdpManager.swift
//  CompassSDK
//
//  The CDP unit: identity resolution + linking, the Server Segments / Server Properties
//  mirrors, device-owned segment writes, publisher consents and the local memory for
//  anonymous consent decisions.
//
//  iOS has no coroutines, so every piece of state lives behind one serial
//  DispatchQueue (`queue`), the per-session resolve memo is a state machine with a list
//  of pending completions that share a single in-flight network call, and every
//  network round-trip captures a `generation` before it starts so a `clearIdentity()`
//  that lands mid-flight makes the response drop on the floor instead of writing the
//  signed-out master back.
//
//  Two unrelated "consents" live here — do not conflate them:
//   - `hasConsent()` is the **CMP** gate (`enableCdp` flag + personalization consent).
//     It gates identity resolve, links, segment writes and profile updates.
//   - `trackCdpConsent` / `getCdpConsent` / `hasCdpConsent` are **publisher** consents
//     recorded in the CDP. They are gated only on the `enableCdp` flag, never on CMP.
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
    func cdpClearMasterId()
    func cdpReadCachedIdentity(sessionId: String) -> CdpCachedIdentity?
    func cdpWriteCachedIdentity(rfv: CdpRfv?, cohorts: [Int], sessionId: String)
    /// Cached rfv/cohorts must read back as **absent** afterwards, so the next resolve mints.
    func cdpClearCachedIdentity()
    /// The legacy (`useg`) segment list — bridged into the CDP store on first resolve and
    /// counted as device-owned when the Server Segments are filtered.
    var cdpLegacySegments: [String] { get }
    func cdpWriteLegacySegments(_ segments: [String])
}

internal final class CdpManager {
    private let api: CdpApiClient
    private let host: CdpHost
    private let segmentsStore: CdpSegmentsStore
    private let serverSegmentsStore: CdpServerSegmentsStore
    private let serverPropertiesStore: CdpServerPropertiesStore
    private let consentMemory: CdpConsentMemoryStore
    private let timezone: () -> String?
    private let clock: () -> Int64

    /// Fired (old, new) whenever the master_id changes. Wired to reset the meter mirror.
    var onMasterIdChanged: ((String?, String) -> Void)?

    /// Fired by `clearIdentity()` with the bucket being wiped, so owners of other
    /// mid-scoped stores (meters) can follow.
    var onIdentityCleared: ((_ account: String?, _ previousMid: String) -> Void)?

    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()

    /// Runs `body` on `queue`, synchronously, whether or not the caller is already on it
    /// (resolve completions are delivered on the queue, so re-entrancy is routine). The
    /// key is per instance, so "am I on *my* queue" is what the check means.
    private func onQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return body() }
        return queue.sync(execute: body)
    }

    /// Delivers a completion off the caller's stack, on `queue`, so every public call has
    /// one delivery contract whether it did work or was gated.
    private func deliver(_ completion: (() -> Void)?) {
        guard let completion = completion else { return }
        queue.async(execute: completion)
    }

    /// Test seam: waits until everything already queued on the manager has run.
    func drainQueueForTesting() { onQueue {} }

    private enum ResolveState { case idle, inFlight, done }
    private var resolveState: ResolveState = .idle
    private var memoSessionId: String?
    private var pending: [() -> Void] = []
    /// Identifies the in-flight resolve; bumped when a reset orphans it.
    private var resolveRunId = 0

    /// Bumped by `clearIdentity()`; a round-trip that started before it drops its result.
    private var generation = 0
    /// The generation the resolve memo belongs to; a reset invalidates it.
    private var resolvedGeneration = 0

    private var identityResolved = false
    private var oneShotCallback: (() -> Void)?

    /// Server Segments for the current master: `server − owned`. MUST be touched on `queue`.
    private var serverSegmentsLocked: [String] = []
    /// Server Properties for the current master, values always strings. MUST be touched on `queue`.
    private var serverPropertiesLocked: [String: String] = [:]
    /// True only after *this* process round-tripped a resolve or link that returned a
    /// master_id **and** mirrored its segments/properties. A warm cache never counts.
    private var identityFreshLocked = false

    private var replayInFlight = false
    private var replayPending: [() -> Void] = []

    init(
        api: CdpApiClient,
        host: CdpHost,
        segmentsStore: CdpSegmentsStore,
        serverSegmentsStore: CdpServerSegmentsStore,
        serverPropertiesStore: CdpServerPropertiesStore,
        consentMemory: CdpConsentMemoryStore,
        timezone: @escaping () -> String? = { TimeZone.current.identifier },
        clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.api = api
        self.host = host
        self.segmentsStore = segmentsStore
        self.serverSegmentsStore = serverSegmentsStore
        self.serverPropertiesStore = serverPropertiesStore
        self.consentMemory = consentMemory
        self.timezone = timezone
        self.clock = clock
        self.queue = DispatchQueue(label: "com.marfeel.cdp.manager")
        self.queue.setSpecific(key: queueKey, value: ())
    }

    // MARK: - Gating & accessors

    /// The CMP gate: `enableCdp` flag **and** personalization consent (unknown allows).
    func hasConsent() -> Bool { host.cdpEnabled && host.cdpConsent != false }

    func isEnabled() -> Bool { host.cdpEnabled }

    func currentMasterId() -> String? { host.cdpReadMasterId() }

    func currentAccountIdString() -> String? { host.cdpAccountId.map(String.init) }

    private var storageMid: String { host.cdpReadMasterId() ?? LOCAL_MID_SENTINEL }

    /// Server Segments known right now, without resolving.
    var serverSegments: [String] { onQueue { serverSegmentsLocked } }

    /// Server Properties known right now, without resolving.
    var serverProperties: [String: String] { onQueue { serverPropertiesLocked } }

    var identityFresh: Bool { onQueue { identityFreshLocked } }

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

    /// The completion is always delivered **on `queue`**, so continuations may read the
    /// locked state directly and must never `queue.sync`.
    func resolveIdentity(completion: (() -> Void)? = nil) {
        guard hasConsent() else {
            if let completion = completion { queue.async(execute: completion) }
            return
        }
        let session = host.cdpSessionId

        queue.async {
            if session != self.memoSessionId || self.generation != self.resolvedGeneration {
                self.memoSessionId = session
                self.resolvedGeneration = self.generation
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
        let masterId = host.cdpReadMasterId()

        // Returning visitor within this session: identity already known. Only skip the
        // network when both mirrors have an entry (even an empty one) — a miss means this
        // master was never mirrored on this device.
        if host.cdpReadCachedIdentity(sessionId: session) != nil, let masterId = masterId {
            let account = currentAccountIdString()
            if let segments = serverSegmentsStore.read(account: account, masterId: masterId),
               let properties = serverPropertiesStore.read(account: account, masterId: masterId) {
                serverSegmentsLocked = segments
                serverPropertiesLocked = properties
                finishResolveLocked()
                return
            }
        }
        guard let siteId = host.cdpAccountId else {
            finishResolveLocked()
            return
        }

        let startGeneration = generation
        resolveRunId += 1
        let runId = resolveRunId
        let params = CdpResolveParams(siteId: siteId, cookieId: host.cdpUserId, masterId: masterId)
        api.resolve(params) { [weak self] response in
            self?.queue.async {
                guard let self = self, runId == self.resolveRunId else { return } // orphaned by a reset
                if self.applyStateLocked(response, session: session, startGeneration: startGeneration) {
                    self.syncServerSegmentsLocked(response.segments)
                    self.syncServerPropertiesLocked(response.properties)
                    self.markIdentityFreshLocked(response)
                }
                self.finishResolveLocked()
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

    /// Called after the mirrors are synced, never inside `applyStateLocked`: a beacon in
    /// between would claim freshness while `useg` / `uvar` still lacked the server data.
    /// A missing master_id means the request failed into `UNKNOWN_CDP_IDENTITY`.
    /// MUST be called on `queue`.
    private func markIdentityFreshLocked(_ response: CdpIdentityResponse) {
        if let masterId = response.masterId, !masterId.isEmpty { identityFreshLocked = true }
    }

    /// The generation is pinned **before** the resolve: a `clearIdentity()` that lands while
    /// the link waits behind a resolve cancels the link instead of re-identifying the
    /// visitor the reset just deleted.
    ///
    /// An empty `type` or `value` is skipped, not posted: `setSiteUserId("")` (sent by
    /// integrations on anonymous pageviews) and the deprecated `cdpDoIdentityLink` reach
    /// here unvalidated, and the failed request would cache empty rfv/cohorts over the
    /// real ones. Matches the web, which only links a truthy site user id.
    func linkIdentity(type: String, value: String, isDeterministic: Bool, completion: (() -> Void)? = nil) {
        guard !type.isEmpty, !value.isEmpty, hasConsent() else { deliver(completion); return }
        let startGeneration = onQueue { generation }
        resolveIdentity { [weak self] in
            guard let self = self, startGeneration == self.generation, let siteId = self.host.cdpAccountId else { completion?(); return }
            let params = CdpLinkParams(
                siteId: siteId,
                idType: type,
                idValue: value,
                isDeterministic: isDeterministic,
                masterId: self.host.cdpReadMasterId()
            )
            self.api.link(params) { [weak self] response in
                guard let self = self else { completion?(); return }
                self.queue.async {
                    if self.applyStateLocked(response, session: self.host.cdpSessionId, startGeneration: startGeneration) {
                        self.syncServerSegmentsLocked(response.segments)
                        self.syncServerPropertiesLocked(response.properties)
                        self.markIdentityFreshLocked(response)
                    }
                    completion?()
                }
            }
        }
    }

    /// Unlinks `type` (every identity of that type when `value` is nil) from the current
    /// master. Refreshes the Server Segments / Properties like a link, but does **not**
    /// mark the identity fresh — a delete resolves no identity.
    func deleteIdentity(type: String, value: String?, completion: (() -> Void)? = nil) {
        guard hasConsent() else { deliver(completion); return }
        let startGeneration = onQueue { generation }
        resolveIdentity { [weak self] in
            guard let self = self,
                  startGeneration == self.generation,
                  let masterId = self.host.cdpReadMasterId(),
                  let siteId = self.host.cdpAccountId else { completion?(); return }
            let params = CdpDeleteParams(siteId: siteId, masterId: masterId, idType: type, idValue: value)
            self.api.delete(params) { [weak self] result in
                guard let self = self, let result = result else { completion?(); return }
                self.queue.async {
                    if self.applyStateLocked(result.identity, session: self.host.cdpSessionId, startGeneration: startGeneration) {
                        self.syncServerSegmentsLocked(result.identity.segments)
                        self.syncServerPropertiesLocked(result.identity.properties)
                    }
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
    ///
    /// `startGeneration` is the `generation` captured before the network call. A
    /// `clearIdentity()` that landed in between means the response belongs to the
    /// signed-out visitor: it is dropped and `false` returned, so no caller can write the
    /// old master back and silently undo a `resetUser()`.
    @discardableResult
    private func applyStateLocked(_ response: CdpIdentityResponse, session: String, startGeneration: Int) -> Bool {
        guard startGeneration == generation else { return false }

        if let masterId = response.masterId, !masterId.isEmpty {
            let old = host.cdpWriteMasterId(masterId)
            let account = currentAccountIdString()
            transferCdpSegments(oldId: old, newId: masterId)
            dropServerSegments(account: account, oldId: old, newId: masterId)
            dropServerProperties(account: account, oldId: old, newId: masterId)
            if old != masterId { onMasterIdChanged?(old, masterId) }
        }
        host.cdpWriteCachedIdentity(rfv: response.rfv, cohorts: response.cohorts, sessionId: session)
        maybeFireOneShotLocked()
        return true
    }

    /// The local wipe behind `resetUser()`. **Synchronous** — a profile read landing
    /// right after cannot hand a beacon the logged-out master. Cached rfv/cohorts are
    /// cleared to absent, not empty: a false cache hit would stop the next resolve from
    /// minting. An in-flight resolve is orphaned (its response is ignored) and its
    /// waiters are released; other in-flight calls drop their result via the generation.
    func clearIdentity() {
        onQueue {
            let account = currentAccountIdString()
            let previous = host.cdpReadMasterId()

            generation += 1
            host.cdpClearMasterId()
            if resolveState == .inFlight { resolveRunId += 1 }
            resolveState = .idle
            memoSessionId = nil
            identityResolved = false
            identityFreshLocked = false
            host.cdpClearCachedIdentity()
            serverSegmentsLocked = []
            serverPropertiesLocked = [:]

            let previousMid = previous ?? segmentsStore.getActiveMid(account: account) ?? LOCAL_MID_SENTINEL
            segmentsStore.clear(account: account, masterId: previousMid)
            serverSegmentsStore.clear(account: account, masterId: previousMid)
            serverPropertiesStore.clear(account: account, masterId: previousMid)
            consentMemory.clear(account: account)
            segmentsStore.setActiveMid(account: account, masterId: LOCAL_MID_SENTINEL)
            onIdentityCleared?(account, previousMid)

            let waiters = pending
            pending = []
            waiters.forEach { $0() }
        }
    }

    /// `POST /cdp/identity/reset/`. On native there are no server-held cookies to expire,
    /// so this is parity plumbing; nil on failure and inert when disabled.
    func resetRemoteIdentity(completion: @escaping (CdpResetResponse?) -> Void) {
        guard isEnabled(), let siteId = host.cdpAccountId else { deliver { completion(nil) }; return }
        api.reset(siteId: siteId, completion: completion)
    }

    // MARK: - Server segments / properties

    /// Persists `server − owned`, where `owned` spans both device-side stores (the legacy
    /// `useg` list and `cdpsegs_`) since either marks an assertion. Keeping backend keys
    /// out of those stores is what stops `clearSegments` / `replaceSegments` from
    /// emitting `segments_remove` for a membership this device never asserted.
    func syncServerSegments(_ segments: [String]?) { onQueue { syncServerSegmentsLocked(segments) } }

    /// MUST be called on `queue`.
    private func syncServerSegmentsLocked(_ segments: [String]?) {
        guard let masterId = host.cdpReadMasterId() else { return }
        let account = currentAccountIdString()
        var owned = Set(host.cdpLegacySegments)
        owned.formUnion(segmentsStore.read(account: account, masterId: masterId))

        serverSegmentsLocked = (segments ?? []).filter { !owned.contains($0) }
        serverSegmentsStore.write(account: account, masterId: masterId, value: serverSegmentsLocked)
    }

    func syncServerProperties(_ properties: [String: String]?) { onQueue { syncServerPropertiesLocked(properties) } }

    /// MUST be called on `queue`.
    private func syncServerPropertiesLocked(_ properties: [String: String]?) {
        guard let masterId = host.cdpReadMasterId() else { return }
        serverPropertiesLocked = properties ?? [:]
        serverPropertiesStore.write(account: currentAccountIdString(), masterId: masterId, value: serverPropertiesLocked)
    }

    /// Removes prune eagerly; adds don't need to, since the next resolve recomputes
    /// `server − owned`. MUST be called on `queue`.
    private func pruneServerSegmentsLocked(_ keep: (String) -> Bool) {
        let next = serverSegmentsLocked.filter(keep)
        guard next.count != serverSegmentsLocked.count else { return }
        serverSegmentsLocked = next
        guard let masterId = host.cdpReadMasterId() else { return }
        serverSegmentsStore.write(account: currentAccountIdString(), masterId: masterId, value: next)
    }

    /// Deliberately **not** carried over the way `transferCdpSegments` carries the
    /// device-owned mirror: this is a snapshot of one master's backend state. On a merge
    /// the winner's own resolve returns the merged set; on a reset the point is a fresh
    /// user. Carrying it would assert stale memberships into `useg`.
    private func dropServerSegments(account: String?, oldId: String?, newId: String) {
        if let oldId = oldId, oldId != newId { serverSegmentsStore.clear(account: account, masterId: oldId) }
        serverSegmentsStore.cleanupExpired(account: account, activeMasterId: newId)
    }

    private func dropServerProperties(account: String?, oldId: String?, newId: String) {
        if let oldId = oldId, oldId != newId { serverPropertiesStore.clear(account: account, masterId: oldId) }
        serverPropertiesStore.cleanupExpired(account: account, activeMasterId: newId)
    }

    /// Resolves first (CMP-gated), then reads the mirror.
    func getServerSegments(completion: @escaping ([String]) -> Void) {
        resolveIdentity { [weak self] in completion(self?.serverSegmentsLocked ?? []) } // on queue
    }

    func getServerProperties(completion: @escaping ([String: String]) -> Void) {
        resolveIdentity { [weak self] in completion(self?.serverPropertiesLocked ?? [:]) } // on queue
    }

    // MARK: - Properties

    /// The master and the generation are read in the same critical section as the
    /// `clearIdentity()` that could invalidate them: either the call never goes out or
    /// its response is dropped.
    func updateProfile(_ properties: [String: String], completion: (() -> Void)? = nil) {
        guard hasConsent(), !properties.isEmpty else { deliver(completion); return }
        queue.async {
            guard let masterId = self.host.cdpReadMasterId(), let siteId = self.host.cdpAccountId else {
                completion?()
                return
            }
            let startGeneration = self.generation
            let params = CdpProfileUpdateParams(siteId: siteId, masterId: masterId, properties: properties)
            self.postUpdateLocked(params, startGeneration: startGeneration, completion: completion)
        }
    }

    // MARK: - Device-owned segments

    func getCdpSegments() -> [String] {
        guard host.cdpEnabled else { return [] }
        return segmentsStore.read(account: currentAccountIdString(), masterId: storageMid)
    }

    func addSegment(_ segment: String) {
        mutateSegments { local in local.contains(segment) ? nil : (local + [segment], [segment], nil) }
    }

    /// Posts `segments_remove` unconditionally — an explicit remove also deletes a
    /// backend-owned membership — and prunes it from the server mirror eagerly.
    func removeSegment(_ segment: String) {
        mutateSegments(afterWrite: { self.pruneServerSegmentsLocked { $0 != segment } }) { local in
            (local.filter { $0 != segment }, nil, [segment])
        }
    }

    /// Posts `segments_remove` for the locally-asserted keys only; empties the server mirror.
    func clearSegments() {
        mutateSegments(afterWrite: { self.pruneServerSegmentsLocked { _ in false } }) { local in
            (local: [], add: nil, remove: local.isEmpty ? nil : local)
        }
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
    private func mutateSegments(
        afterWrite: (() -> Void)? = nil,
        _ transform: @escaping (_ local: [String]) -> (local: [String], add: [String]?, remove: [String]?)?
    ) {
        guard host.cdpEnabled else { return }
        queue.async {
            let account = self.currentAccountIdString()
            let mid = self.storageMid
            let local = self.segmentsStore.read(account: account, masterId: mid)
            guard let result = transform(local) else { return }
            self.segmentsStore.write(account: account, masterId: mid, value: result.local)
            afterWrite?()
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

    /// Bridge the legacy (`useg`) segment store into the CDP store on first identity
    /// resolve, mirroring the web `mergeLegacySegmentsIntoCdpStorage` union. Must run
    /// BEFORE `reconcileSegments` so the unioned set is what gets pushed as
    /// `segments_add`. No-op without a real master_id (leaves the legacy list untouched).
    func mergeLegacySegments() {
        guard hasConsent() else { return }
        queue.async {
            guard let masterId = self.host.cdpReadMasterId() else { return }
            let account = self.currentAccountIdString()
            let legacy = self.host.cdpLegacySegments
            let stored = self.segmentsStore.read(account: account, masterId: masterId)
            let merged = self.dedup(stored + legacy)
            if Set(merged) != Set(stored) {
                self.segmentsStore.write(account: account, masterId: masterId, value: merged)
            }
            if Set(merged) != Set(legacy) {
                self.host.cdpWriteLegacySegments(merged)
            }
        }
    }

    /// MUST be called on `queue`.
    private func postSegmentChangeLocked(segmentsAdd: [String]?, segmentsRemove: [String]?) {
        guard hasConsent(), let masterId = host.cdpReadMasterId(), let siteId = host.cdpAccountId else { return }
        let startGeneration = generation
        let params = CdpProfileUpdateParams(siteId: siteId, masterId: masterId, segmentsAdd: segmentsAdd, segmentsRemove: segmentsRemove)
        postUpdateLocked(params, startGeneration: startGeneration)
    }

    /// `/update/` is only ever sent with a master, and a successful answer always echoes
    /// one; an answer without it is the fail-open `UNKNOWN_CDP_IDENTITY` and is dropped so
    /// a failed write (every `setUserVar`, every segment change) can't blank the cached
    /// rfv/cohorts for the rest of the session. MUST be called on `queue`.
    private func postUpdateLocked(_ params: CdpProfileUpdateParams, startGeneration: Int, completion: (() -> Void)? = nil) {
        api.update(params) { [weak self] response in
            guard let self = self else { completion?(); return }
            self.queue.async {
                if let masterId = response.masterId, !masterId.isEmpty {
                    self.applyStateLocked(response, session: self.host.cdpSessionId, startGeneration: startGeneration)
                }
                completion?()
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

    // MARK: - Publisher consents

    /// `POST /cdp/consents/record/`. Deliberately **not** gated on CMP consent, unlike
    /// every sibling: a visitor who declines tracking and then accepts the privacy policy
    /// has still accepted it, and failing to record that destroys the proof this feature
    /// exists to keep. Every call is sent — no client-side dedupe.
    func trackCdpConsent(_ decision: CdpConsent, completion: @escaping (CdpConsentRecordResponse?) -> Void) {
        guard isEnabled(), !decision.consentId.isEmpty, let siteId = host.cdpAccountId else {
            deliver { completion(nil) }
            return
        }

        queue.async {
            let masterId = self.host.cdpReadMasterId()
            let startGeneration = self.generation
            var params = CdpConsentRecordParams(
                siteId: siteId,
                masterId: masterId,
                consentId: decision.consentId,
                consentVersionId: decision.versionId,
                status: decision.status,
                metadata: decision.metadata ?? [:],
                timezone: self.timezone()
            )
            if let email = decision.email, !email.isEmpty {
                let subject = consentEmailIdentity(email)
                params.idType = subject.idType
                params.idValue = subject.idValue
            }

            self.api.recordConsent(params) { [weak self] result in
                guard let self = self else { completion(result); return }
                self.queue.async {
                    self.adoptCanonicalMasterLocked(sent: masterId, result: result, startGeneration: startGeneration)

                    if let result = result, result.recorded, masterId == nil {
                        self.consentMemory.remember(
                            account: self.currentAccountIdString(),
                            consentId: decision.consentId,
                            decision: CdpRememberedConsentDecision(versionId: decision.versionId, status: decision.status, ts: self.clock())
                        )
                    }
                    completion(result)
                }
            }
        }
    }

    /// A record that came back under a different master was merged into that winner
    /// server-side. Adopted through the link response's own path (`applyStateLocked`),
    /// keeping the cached rfv/cohorts until the next resolve refreshes them; never
    /// without a master of our own (the decision is remembered instead). MUST be on `queue`.
    private func adoptCanonicalMasterLocked(sent: String?, result: CdpConsentRecordResponse?, startGeneration: Int) {
        guard let sent = sent, let returned = result?.masterId, !returned.isEmpty, returned != sent, isValidUuid(returned) else { return }
        let session = host.cdpSessionId
        let cached = host.cdpReadCachedIdentity(sessionId: session)
        applyStateLocked(
            CdpIdentityResponse(masterId: returned, rfv: cached?.rfv, cohorts: cached?.cohorts ?? []),
            session: session,
            startGeneration: startGeneration
        )
    }

    /// Re-records every decision remembered under the `local` bucket now that a master
    /// exists, then forgets only those the server answered `recorded: true`. Memoised
    /// while in flight (callers share the run), re-armed on settle.
    func replayConsentDecisions(completion: (() -> Void)? = nil) {
        queue.async {
            completion.map { self.replayPending.append($0) }
            guard !self.replayInFlight else { return }
            self.replayInFlight = true
            self.runConsentReplayLocked()
        }
    }

    /// MUST be called on `queue`.
    private func runConsentReplayLocked() {
        guard isEnabled(), let masterId = host.cdpReadMasterId(), let siteId = host.cdpAccountId else {
            finishReplayLocked()
            return
        }
        let account = currentAccountIdString()
        let decisions = consentMemory.getRemembered(account: account)
        guard !decisions.isEmpty else {
            finishReplayLocked()
            return
        }

        let group = DispatchGroup()
        let recordedQueue = DispatchQueue(label: "com.marfeel.cdp.replay.results")
        var recorded: [String] = []

        for (consentId, decision) in decisions {
            group.enter()
            let params = CdpConsentRecordParams(
                siteId: siteId,
                masterId: masterId,
                consentId: consentId,
                consentVersionId: decision.versionId,
                status: decision.status
            )
            api.recordConsent(params) { result in
                if let result = result, result.recorded {
                    recordedQueue.sync { recorded.append(consentId) }
                }
                group.leave()
            }
        }

        group.notify(queue: queue) { [weak self] in
            guard let self = self else { return }
            let done = recordedQueue.sync { recorded }
            if !done.isEmpty { self.consentMemory.forget(account: account, consentIds: done) }
            self.finishReplayLocked()
        }
    }

    /// MUST be called on `queue`.
    private func finishReplayLocked() {
        replayInFlight = false
        let callbacks = replayPending
        replayPending = []
        callbacks.forEach { $0() }
    }

    /// `GET /cdp/consents/catalog/`. Not CMP-gated: a prompt has to render before consent is known.
    func getCdpConsent(_ ref: CdpConsentRef, completion: @escaping (CdpConsentDefinition?) -> Void) {
        guard isEnabled(), !ref.consentId.isEmpty, let siteId = host.cdpAccountId else {
            deliver { completion(nil) }
            return
        }
        api.fetchConsentCatalog(siteId: siteId, consentId: ref.consentId, versionId: ref.versionId) { items in
            completion(items?.first.map(CdpManager.toConsentDefinition))
        }
    }

    /// Not public: the SDK exposes only the boolean `hasCdpConsent`, which reduces this.
    func consentCheck(_ query: CdpConsentQuery, completion: @escaping (CdpConsentCheck?) -> Void) {
        guard isEnabled(), !query.consentId.isEmpty else {
            deliver { completion(nil) }
            return
        }

        let masterId = host.cdpReadMasterId()
        let subject = query.email.flatMap { $0.isEmpty ? nil : consentEmailIdentity($0) }

        if masterId == nil && subject == nil {
            let status = rememberedConsentStatus(consentId: query.consentId, version: query.versionId)
            deliver { completion(status) }
            return
        }
        guard let siteId = host.cdpAccountId else {
            deliver { completion(nil) }
            return
        }

        let params = CdpConsentCheckParams(
            siteId: siteId,
            consentId: query.consentId,
            consentVersionId: query.versionId,
            masterId: masterId,
            idType: subject?.idType,
            idValue: subject?.idValue
        )
        api.fetchConsentStatus(params) { result in
            completion(result.map(CdpManager.toConsentStatus))
        }
    }

    /// False — never nil — on transport errors and when CDP is disabled.
    func hasCdpConsent(_ query: CdpConsentQuery, completion: @escaping (Bool) -> Void) {
        guard isEnabled() else { deliver { completion(false) }; return }
        consentCheck(query) { status in completion(status?.granted == true) }
    }

    /// Mirrors the server's rule: with a requested version, only an accept at exactly that
    /// version grants; without one, any accepted version grants and the answered version
    /// is echoed as `versionId`.
    private func rememberedConsentStatus(consentId: String, version: String?) -> CdpConsentCheck {
        let decisions = consentMemory.getRemembered(account: currentAccountIdString())
        guard let entry = decisions[consentId] else {
            return CdpConsentCheck(masterId: nil, consentId: consentId, versionId: version ?? "", granted: false, answered: false)
        }
        let versionId = version ?? entry.versionId
        return CdpConsentCheck(
            masterId: nil,
            consentId: consentId,
            versionId: versionId,
            granted: entry.status == .accepted && versionId == entry.versionId,
            answered: true,
            status: entry.status,
            answeredVersionId: entry.versionId
        )
    }

    private static func toConsentStatus(_ result: CdpConsentCheckResponse) -> CdpConsentCheck {
        return CdpConsentCheck(
            masterId: result.masterId.flatMap { $0.isEmpty ? nil : $0 },
            consentId: result.consentId,
            versionId: result.consentVersionId ?? "",
            granted: result.granted,
            answered: result.answered,
            status: result.status.flatMap { $0.isEmpty ? nil : CdpConsentStatus.fromWire($0) },
            answeredVersionId: result.answeredVersionId.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func toConsentDefinition(_ item: CdpConsentCatalogItem) -> CdpConsentDefinition {
        return CdpConsentDefinition(
            consentId: item.consentId,
            name: item.name,
            purpose: item.purpose,
            mandatory: item.mandatory,
            acceptMethod: item.acceptMethod,
            showPolicy: CdpConsentShowPolicy.fromWire(item.showPolicy),
            version: item.version.map {
                CdpConsentVersion(versionId: $0.versionId, label: $0.label, date: $0.date, displayPrompt: $0.displayPrompt, errorMessage: $0.errorMessage, metadata: $0.metadata)
            }
        )
    }

    // MARK: - Beacon data

    func getUserProfile() -> CdpData {
        guard host.cdpEnabled else { return CdpData(masterId: nil, rfv: nil, cohorts: []) }
        let cached = host.cdpReadCachedIdentity(sessionId: host.cdpSessionId)
        return CdpData(masterId: host.cdpReadMasterId(), rfv: cached?.rfv, cohorts: cached?.cohorts ?? [], identityFresh: identityFresh)
    }
}
