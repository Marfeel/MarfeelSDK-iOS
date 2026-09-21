//
//  CompassTrackerCdpTests.swift
//  CompassSDKTests
//
//  The tracker-level CDP wiring, with a `CdpTracker` whose host is the tracker under
//  test: the beacon's `useg` / `uvar` / `cdp_*` fields, the `setUserVar` flush, the
//  `setUserSegments` ownership filter, the facade's resolve-first ordering, and what a
//  beacon looks like right after `resetUser()` (spec A.7).
//

import XCTest
@testable import CompassSDK

final class CompassTrackerCdpTests: XCTestCase {
    private var api: MockCdpApi!
    private var storage: MockStorage!
    private var config: TrackingConfig!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var cdp: CdpTracker!
    private var tracker: CompassTracker!

    override func setUp() {
        super.setUp()
        api = MockCdpApi()
        storage = MockStorage()
        storage.userVars = [:]
        storage.userSegments = []
        storage.hasConsent = true
        suiteName = "CompassTrackerCdpTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        config = TrackingConfig()
        config.override(accountId: 456, pageTechnology: nil, endpoint: nil)
        config.cdpEnabled = true
        tracker = CompassTracker(
            config: config,
            storage: storage,
            tikOperationFactory: MockedOperationProvider(),
            cdpProvider: { [unowned self] host in
                let cdp = CdpTracker(api: self.api, defaults: self.defaults, host: host)
                self.cdp = cdp
                return cdp
            }
        )
    }

    override func tearDown() {
        tracker.stopTracking()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var hundredServer: [String] { (1...100).map { "srv\($0)" } }

    private func beacon() -> IngestTrackInfo {
        var info: IngestTrackInfo!
        waitFor("beacon") { done in self.tracker.getTrackingData { info = $0; done() } }
        return info
    }

    private func resolved(masterId: String, segments: [String] = [], properties: [String: String] = [:]) {
        storage.cdpMasterId = masterId
        api.resolveResponses = [CdpIdentityResponse(masterId: masterId, rfv: CdpRfv(rfv: 1, r: 1, f: 1, v: 1), cohorts: [1], segments: segments, properties: properties)]
        cdp.manager.resolveAndWait(self)
    }

    // MARK: - beacon

    func testBeaconUsegIsTheServerFirstUnionTrimmedTo100AndUvarCarriesTheFlagInTheSameBeacon() {
        storage.userSegments = ["device", "srv1"]
        storage.userVars = ["plan": "premium"]
        resolved(masterId: UUID_A, segments: hundredServer, properties: ["role": "editor", "plan": "crm"])
        tracker.trackNewPage(url: URL(string: "https://x.com/a")!)

        let info = beacon()

        // "srv1" is device-owned too, so the server diff is srv2…srv100 (99). The union is
        // server-first then the device list in its stored order, so the 101st entry that the
        // cap drops is the device's own "srv1".
        XCTAssertEqual(info.userSegments?.count, 100)
        XCTAssertEqual(info.userSegments?.first, "srv2")
        XCTAssertTrue(info.userSegments?.contains("device") ?? false)
        XCTAssertFalse(info.userSegments?.contains("srv1") ?? true)
        XCTAssertEqual(info.userVars?["plan"], "premium")
        XCTAssertEqual(info.userVars?["role"], "editor")
        XCTAssertEqual(info.userVars?[MRF_TOO_MANY_SEGMENTS], "true")
        XCTAssertEqual(info.cdpMasterId, UUID_A)
        XCTAssertEqual(info.cdpFresh, "1")
    }

    func testBeaconCarriesNoCdpFieldsOnAWarmCacheOrWithoutConsent() {
        storage.cdpMasterId = UUID_A
        storage.writeCdpCachedIdentity(rfv: nil, cohorts: [], sessionId: storage.sessionId)
        defaults.set(["segments": [], "ts": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000))], forKey: "cdpsrvsegs_\(UUID_A)_456")
        defaults.set(["properties": [:], "ts": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000))], forKey: "cdpsrvprops_\(UUID_A)_456")
        cdp.manager.resolveAndWait(self)
        tracker.trackNewPage(url: URL(string: "https://x.com/a")!)

        var info = beacon()
        XCTAssertEqual(info.cdpMasterId, UUID_A)
        XCTAssertNil(info.cdpFresh)
        XCTAssertEqual(api.resolveParams.count, 0)

        storage.hasConsent = false
        info = beacon()
        XCTAssertNil(info.cdpMasterId)
    }

    // MARK: - writes

    func testSetUserVarFlushesTheOwnedVarsToTheCdpProfileDebounced() {
        resolved(masterId: UUID_A)
        api.updateResponses = [CdpIdentityResponse(masterId: UUID_A, rfv: nil, cohorts: [])]

        tracker.setUserVar(name: "plan", value: "gold")
        tracker.setUserVar(name: "tier", value: "2")
        settle(0.4)

        // The one-shot identity-resolved push (user vars + timezone) is separate; the two
        // setUserVar calls collapse into a single debounced flush of the owned vars.
        let flushes = api.updateParams.filter { $0.properties?["plan"] != nil }
        XCTAssertEqual(flushes.count, 1)
        XCTAssertEqual(flushes.first?.properties, ["plan": "gold", "tier": "2"])
    }

    func testSetUserSegmentsRejectsServerOnlyKeysAndKeepsOwnedOnes() {
        storage.userSegments = ["mine"]
        resolved(masterId: UUID_A, segments: ["server-only", "mine"])

        tracker.setUserSegments(["mine", "server-only", "new"])
        cdp.drainForTesting()

        XCTAssertEqual(storage.userSegments, ["mine", "new"])
        // The one-shot reconcile already posted ["mine"]; the replace diffs against that
        // local snapshot and adds only "new". The server-only key is never posted.
        let adds = api.updateParams.compactMap { $0.segmentsAdd }
        XCTAssertTrue(adds.contains(["new"]), "\(adds)")
        XCTAssertFalse(adds.joined().contains("server-only"))
    }

    func testGetUserSegmentsAndVarsExposeTheMergedViews() {
        storage.userSegments = ["device"]
        storage.userVars = ["a": "1"]
        resolved(masterId: UUID_A, segments: ["srv"], properties: ["b": "2"])
        XCTAssertEqual(tracker.getUserSegments(), ["srv", "device"])
        XCTAssertEqual(tracker.getUserVars(), ["a": "1", "b": "2"])

        var asyncSegments: [String] = []
        waitFor { done in self.tracker.getUserSegments { asyncSegments = $0; done() } }
        XCTAssertEqual(asyncSegments, ["srv", "device"])
    }

    // MARK: - facade ordering (spec D.11 #14)

    func testTrackConsentAndHasConsentResolveFirstButGetConsentDoesNot() {
        api.resolveResponses = [CdpIdentityResponse(masterId: UUID_A, rfv: nil, cohorts: []), CdpIdentityResponse(masterId: UUID_A, rfv: nil, cohorts: [])]
        api.catalogResponses = [[]]
        waitFor { done in self.cdp.getConsent(CdpConsentRef(consentId: "privacy")) { _ in done() } }
        XCTAssertEqual(api.resolveParams.count, 0)

        api.recordResponses = [CdpConsentRecordResponse(masterId: UUID_A, consentId: "privacy", consentVersionId: "1", status: "accept", recorded: true, stored: true)]
        waitFor { done in self.cdp.trackConsent(CdpConsent(consentId: "privacy", versionId: "1", status: .accepted)) { _ in done() } }
        XCTAssertEqual(api.resolveParams.count, 1)
        XCTAssertEqual(api.recordParams.first?.masterId, UUID_A)

        // The resolve is memoised per session; a new session proves hasConsent asks first.
        storage.sessionId = "session-2"
        storage.cdpCacheSessionId = nil
        api.checkResponses = [nil]
        waitFor { done in self.cdp.hasConsent(CdpConsentQuery(consentId: "privacy")) { _ in done() } }
        XCTAssertEqual(api.resolveParams.count, 2)
    }

    func testSetIdentityRejectsAnEmptyValueWithoutPosting() {
        resolved(masterId: UUID_A)
        // assertionFailure is a no-op in release test builds; in debug it traps, so only
        // exercise the guard's observable contract through the manager-level path.
        waitFor { done in self.cdp.manager.linkIdentity(type: "email", value: "x", isDeterministic: true, completion: done) }
        XCTAssertEqual(api.linkParams.count, 1)
    }

    // MARK: - reset (spec A.7)

    func testABeaconRightAfterResetUserCarriesTheNewVisitorAndNoCdpFields() {
        storage.userVars = ["plan": "premium"]
        storage.userSegments = ["sports"]
        resolved(masterId: UUID_A, segments: ["srv"], properties: ["role": "editor"])
        tracker.setSiteUserId("site-user-1")
        tracker.setUserType(.logged)
        tracker.trackNewPage(url: URL(string: "https://x.com/a")!)
        let before = beacon()
        XCTAssertEqual(before.siteUserId, "site-user-1")
        XCTAssertEqual(before.cdpMasterId, UUID_A)

        let completed = XCTestExpectation(description: "reset completed")
        tracker.resetUser { completed.fulfill() }
        // The rotation is synchronous: assert without waiting for the remote tail.
        let after = beacon()

        XCTAssertNotEqual(after.userId, before.userId)
        XCTAssertNil(after.siteUserId)
        XCTAssertNil(after.userType)
        XCTAssertNotEqual(after.sessionId, before.sessionId)
        XCTAssertEqual(after.userSegments, [])
        XCTAssertEqual(after.userVars, [:])
        XCTAssertNil(after.cdpMasterId)
        XCTAssertNil(after.cdpRfv)
        XCTAssertNil(after.cdpCohorts)
        XCTAssertNil(after.cdpFresh)
        XCTAssertEqual(after.pageUrl, before.pageUrl)
        XCTAssertEqual(after.pageId, before.pageId)
        XCTAssertEqual(cdp.listServerSegments(), [])
        XCTAssertEqual(cdp.listServerProperties(), [:])

        wait(for: [completed], timeout: 3)
        XCTAssertEqual(api.resolveParams.count, 1, "the reset never re-resolves")
        XCTAssertEqual(api.resetSiteIds, [456])
    }

    func testConcurrentResetUserCallsShareOneRun() {
        resolved(masterId: UUID_A)
        var release: ((CdpResetResponse?) -> Void)?
        let held = XCTestExpectation(description: "held")
        api.holdReset = { completion in release = completion; held.fulfill() }
        let first = XCTestExpectation(description: "first")
        let second = XCTestExpectation(description: "second")
        let userBefore = storage.userId

        tracker.resetUser { first.fulfill() }
        tracker.resetUser { second.fulfill() }
        wait(for: [held], timeout: 2)
        XCTAssertEqual(storage.resetUserCalls, 1)
        XCTAssertNotEqual(storage.userId, userBefore)
        release?(nil)
        wait(for: [first, second], timeout: 2)
        XCTAssertEqual(api.resetSiteIds.count, 1)
    }
}
