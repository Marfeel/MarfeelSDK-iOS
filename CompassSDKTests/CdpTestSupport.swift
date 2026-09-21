//
//  CdpTestSupport.swift
//  CompassSDKTests
//
//  In-memory stand-ins for everything `CdpManager` is wired to: a scripted API client
//  (no network), a host whose fields the test can read and poke, and a `UserDefaults`
//  suite that is wiped between tests.
//

import Foundation
import XCTest
@testable import CompassSDK

let UUID_A = "550E8400-E29B-41D4-A716-446655440000"
let UUID_B = "550E8400-E29B-41D4-A716-446655440001"

/// Scripted `CdpApiClient`: every call records its params and answers from a queue of
/// canned responses (or a handler), off the caller's thread like the real transport.
final class MockCdpApi: CdpApiClient {
    private let lock = NSLock()
    private let callbackQueue = DispatchQueue(label: "mock.cdp.api")

    var resolveResponses: [CdpIdentityResponse] = []
    var linkResponses: [CdpIdentityResponse] = []
    var updateResponses: [CdpIdentityResponse] = []
    var deleteResponses: [CdpDeleteResponse?] = []
    var resetResponses: [CdpResetResponse?] = []
    var recordResponses: [CdpConsentRecordResponse?] = []
    var catalogResponses: [[CdpConsentCatalogItem]?] = []
    var checkResponses: [CdpConsentCheckResponse?] = []

    /// When set, a resolve does not answer until the test calls the release closure.
    var holdResolve: ((@escaping (CdpIdentityResponse) -> Void) -> Void)?
    var holdUpdate: ((@escaping (CdpIdentityResponse) -> Void) -> Void)?
    var holdRecord: ((@escaping (CdpConsentRecordResponse?) -> Void) -> Void)?
    var holdReset: ((@escaping (CdpResetResponse?) -> Void) -> Void)?

    private(set) var resolveParams: [CdpResolveParams] = []
    private(set) var linkParams: [CdpLinkParams] = []
    private(set) var updateParams: [CdpProfileUpdateParams] = []
    private(set) var deleteParams: [CdpDeleteParams] = []
    private(set) var resetSiteIds: [Int] = []
    private(set) var recordParams: [CdpConsentRecordParams] = []
    private(set) var catalogCalls: [(siteId: Int, consentId: String, versionId: String?)] = []
    private(set) var checkParams: [CdpConsentCheckParams] = []

    init() {
        super.init(session: .shared, baseUrl: URL(string: "https://unused.invalid"))
    }

    private func next<T>(_ list: inout [T], fallback: T) -> T {
        lock.lock(); defer { lock.unlock() }
        return list.isEmpty ? fallback : list.removeFirst()
    }

    private func deliver<T>(_ value: T, _ completion: @escaping (T) -> Void) {
        callbackQueue.async { completion(value) }
    }

    override func resolve(_ params: CdpResolveParams, completion: @escaping (CdpIdentityResponse) -> Void) {
        lock.lock(); resolveParams.append(params); lock.unlock()
        if let hold = holdResolve { hold(completion); return }
        deliver(next(&resolveResponses, fallback: UNKNOWN_CDP_IDENTITY), completion)
    }

    override func link(_ params: CdpLinkParams, completion: @escaping (CdpIdentityResponse) -> Void) {
        lock.lock(); linkParams.append(params); lock.unlock()
        deliver(next(&linkResponses, fallback: UNKNOWN_CDP_IDENTITY), completion)
    }

    override func update(_ params: CdpProfileUpdateParams, completion: @escaping (CdpIdentityResponse) -> Void) {
        lock.lock(); updateParams.append(params); lock.unlock()
        if let hold = holdUpdate { hold(completion); return }
        deliver(next(&updateResponses, fallback: UNKNOWN_CDP_IDENTITY), completion)
    }

    override func delete(_ params: CdpDeleteParams, completion: @escaping (CdpDeleteResponse?) -> Void) {
        lock.lock(); deleteParams.append(params); lock.unlock()
        deliver(next(&deleteResponses, fallback: nil), completion)
    }

    override func reset(siteId: Int, completion: @escaping (CdpResetResponse?) -> Void) {
        lock.lock(); resetSiteIds.append(siteId); lock.unlock()
        if let hold = holdReset { hold(completion); return }
        deliver(next(&resetResponses, fallback: nil), completion)
    }

    override func recordConsent(_ params: CdpConsentRecordParams, completion: @escaping (CdpConsentRecordResponse?) -> Void) {
        lock.lock(); recordParams.append(params); lock.unlock()
        if let hold = holdRecord { hold(completion); return }
        deliver(next(&recordResponses, fallback: nil), completion)
    }

    override func fetchConsentCatalog(siteId: Int, consentId: String, versionId: String?, completion: @escaping ([CdpConsentCatalogItem]?) -> Void) {
        lock.lock(); catalogCalls.append((siteId, consentId, versionId)); lock.unlock()
        deliver(next(&catalogResponses, fallback: nil), completion)
    }

    override func fetchConsentStatus(_ params: CdpConsentCheckParams, completion: @escaping (CdpConsentCheckResponse?) -> Void) {
        lock.lock(); checkParams.append(params); lock.unlock()
        deliver(next(&checkResponses, fallback: nil), completion)
    }

    override func fetchMeters(siteId: String, masterId: String, completion: @escaping ([MeterState]?) -> Void) {
        deliver(nil, completion)
    }

    override func incrementMeter(name: String, siteId: String, masterId: String, completion: @escaping (IncrementResult) -> Void) {
        deliver(IncrementResult(status: 0, state: nil), completion)
    }
}

/// The tracker-side hooks as plain fields.
final class MockCdpHost: CdpHost {
    var cdpEnabled = true
    var cdpAccountId: Int? = 456
    var cdpUserId = "cookie-1"
    var cdpSessionId = "session-1"
    var cdpConsent: Bool? = true
    var cdpUserVars: [String: String] = [:]
    var masterId: String?
    var cached: CdpCachedIdentity?
    var cachedSession: String?
    var legacySegments: [String] = []

    private let lock = NSLock()

    func cdpReadMasterId() -> String? { lock.lock(); defer { lock.unlock() }; return masterId }
    func cdpWriteMasterId(_ id: String) -> String? { lock.lock(); defer { lock.unlock() }; let old = masterId; masterId = id; return old }
    func cdpClearMasterId() { lock.lock(); masterId = nil; lock.unlock() }
    func cdpReadCachedIdentity(sessionId: String) -> CdpCachedIdentity? { lock.lock(); defer { lock.unlock() }; return sessionId == cachedSession ? cached : nil }
    func cdpWriteCachedIdentity(rfv: CdpRfv?, cohorts: [Int], sessionId: String) {
        lock.lock(); cached = CdpCachedIdentity(rfv: rfv, cohorts: cohorts); cachedSession = sessionId; lock.unlock()
    }
    func cdpClearCachedIdentity() { lock.lock(); cached = nil; cachedSession = nil; lock.unlock() }
    var cdpLegacySegments: [String] { lock.lock(); defer { lock.unlock() }; return legacySegments }
    func cdpWriteLegacySegments(_ segments: [String]) { lock.lock(); legacySegments = segments; lock.unlock() }
}

/// Everything wired together over a fresh, isolated `UserDefaults` suite.
final class CdpTestEnv {
    let api = MockCdpApi()
    let host = MockCdpHost()
    let defaults: UserDefaults
    let suiteName: String
    let segmentsStore: CdpSegmentsStore
    let serverSegmentsStore: CdpServerSegmentsStore
    let serverPropertiesStore: CdpServerPropertiesStore
    let consentMemory: CdpConsentMemoryStore
    let manager: CdpManager

    var masterIdChanges: [(String?, String)] = []
    var clearedBuckets: [(String?, String)] = []
    var timezone: String? = "Europe/Madrid"
    var now: Int64 = 1_000

    var account: String { String(host.cdpAccountId ?? 0) }

    init(consentMemory: CdpConsentMemoryStore? = nil, file: StaticString = #file, line: UInt = #line) {
        suiteName = "CdpTestEnv-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        segmentsStore = CdpSegmentsStore(defaults: defaults)
        serverSegmentsStore = CdpServerSegmentsStore(defaults: defaults)
        serverPropertiesStore = CdpServerPropertiesStore(defaults: defaults)
        self.consentMemory = consentMemory ?? CdpConsentMemoryStore(defaults: defaults)

        var tz: () -> String? = { nil }
        var clock: () -> Int64 = { 0 }
        manager = CdpManager(
            api: api,
            host: host,
            segmentsStore: segmentsStore,
            serverSegmentsStore: serverSegmentsStore,
            serverPropertiesStore: serverPropertiesStore,
            consentMemory: self.consentMemory,
            timezone: { tz() },
            clock: { clock() }
        )
        tz = { [unowned self] in self.timezone }
        clock = { [unowned self] in self.now }
        manager.onMasterIdChanged = { [unowned self] old, new in self.masterIdChanges.append((old, new)) }
        manager.onIdentityCleared = { [unowned self] account, mid in self.clearedBuckets.append((account, mid)) }
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// A warm returning visitor: master + session-tagged cache + both mirrors present.
    func warmVisitor(segments: [String] = [], properties: [String: String] = [:]) {
        host.masterId = UUID_A
        host.cached = CdpCachedIdentity(rfv: CdpRfv(rfv: 1, r: 1, f: 1, v: 1), cohorts: [1])
        host.cachedSession = host.cdpSessionId
        serverSegmentsStore.write(account: account, masterId: UUID_A, value: segments)
        serverPropertiesStore.write(account: account, masterId: UUID_A, value: properties)
    }
}

extension XCTestCase {
    /// Runs `body` and waits for it to call `done`, failing after `timeout`.
    func waitFor(_ description: String = "async", timeout: TimeInterval = 3, _ body: (_ done: @escaping () -> Void) -> Void) {
        let expectation = XCTestExpectation(description: description)
        body { expectation.fulfill() }
        wait(for: [expectation], timeout: timeout)
    }

    /// Lets the manager's queues drain.
    func settle(_ seconds: TimeInterval = 0.15) {
        let expectation = XCTestExpectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { expectation.fulfill() }
        wait(for: [expectation], timeout: seconds + 2)
    }
}

extension CdpManager {
    /// Test convenience: resolve and block until the completion fires.
    func resolveAndWait(_ testCase: XCTestCase) {
        testCase.waitFor("resolve") { done in self.resolveIdentity(completion: done) }
    }
}
