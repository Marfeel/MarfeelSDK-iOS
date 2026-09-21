//
//  UserResetTests.swift
//  CompassSDKTests
//
//  `resetUser()`: the shared, timer-bounded run; the local rotation over a real
//  plist-backed storage (what a beacon fired right after must look like); the beacon's
//  cdp_fresh field; and the public-surface pin.
//

import XCTest
@testable import CompassSDK

final class UserResetterTests: XCTestCase {
    private var userId = UUID().uuidString
    private var rotations = 0
    private var remoteCalls = 0
    private var userIdSeenByRemote: [String] = []
    private let lock = NSLock()

    private func rotate() {
        lock.lock(); defer { lock.unlock() }
        rotations += 1
        userId = UUID().uuidString
    }

    private func resetter(
        remote: ((@escaping () -> Void) -> Void)? = nil,
        timeout: TimeInterval = 5
    ) -> UserResetter {
        return UserResetter(
            rotateLocalUser: { [unowned self] in self.rotate() },
            clearRemoteState: remote ?? { [unowned self] completion in
                self.lock.lock(); self.remoteCalls += 1; self.userIdSeenByRemote.append(self.userId); self.lock.unlock()
                completion()
            },
            remoteTimeout: timeout
        )
    }

    func testRotatesSynchronouslyBeforeStartReturns() {
        let before = userId
        resetter().start()
        XCTAssertNotEqual(before, userId)
        XCTAssertEqual(rotations, 1)
    }

    func testRotatesBeforeAskingTheServer() {
        let before = userId
        waitFor { done in self.resetter().reset(completion: done) }
        XCTAssertEqual(remoteCalls, 1)
        XCTAssertNotEqual(before, userIdSeenByRemote.first)
        XCTAssertEqual(userId, userIdSeenByRemote.first)
    }

    func testConcurrentResetsShareOneRun() {
        var release: (() -> Void)?
        let held = XCTestExpectation(description: "held")
        let resetter = resetter(remote: { completion in release = completion; held.fulfill() })
        let first = resetter.start()
        let second = resetter.start()
        XCTAssertTrue(first === second)
        wait(for: [held], timeout: 2)
        XCTAssertEqual(rotations, 1)
        release?()
        waitFor { done in first.onComplete(done) }
    }

    func testResetsAgainOnceTheFirstRunSettled() {
        let resetter = resetter()
        waitFor { done in resetter.reset(completion: done) }
        waitFor { done in resetter.reset(completion: done) }
        XCTAssertEqual(rotations, 2)
        XCTAssertEqual(remoteCalls, 2)
    }

    func testCompletesEvenWhenTheRemoteCleanupNeverSettles() {
        let resetter = resetter(remote: { _ in }, timeout: 0.1)
        waitFor(timeout: 2) { done in resetter.reset(completion: done) }
        XCTAssertEqual(rotations, 1)
    }

    func testASecondCallerWaitsForTheInFlightRunInsteadOfCompletingEarly() {
        var release: (() -> Void)?
        let held = XCTestExpectation(description: "held")
        let resetter = resetter(remote: { completion in release = completion; held.fulfill() })
        var firstDone = false
        var secondDone = false
        resetter.reset { firstDone = true }
        wait(for: [held], timeout: 2)
        resetter.reset { secondDone = true }
        settle(0.05)
        XCTAssertFalse(secondDone)
        release?()
        settle(0.05)
        XCTAssertTrue(firstDone)
        XCTAssertTrue(secondDone)
        XCTAssertEqual(rotations, 1)
    }
}

/// The rotation against a real plist-backed storage in a scratch documents directory.
final class UserRotationStorageTests: XCTestCase {
    private var storage: PListCompassStorage!

    override func setUp() {
        super.setUp()
        storage = PListCompassStorage()
        storage.resetUser()
        storage.setConsent(true)
    }

    private func signedInUser() {
        _ = storage.userId
        storage.suid = "site-user-1"
        _ = storage.firstVisit
        storage.addVisit()
        storage.addVisit()
        storage.addUserVar(name: "plan", value: "premium")
        storage.addUserSegment("sports")
        storage.addSessionVar(name: "sv", value: "1")
        storage.setLandingPage("https://x.com/landing")
        _ = storage.writeCdpMasterId(UUID_A)
        storage.writeCdpCachedIdentity(rfv: CdpRfv(rfv: 1, r: 1, f: 1, v: 1), cohorts: [1], sessionId: storage.sessionId)
    }

    func testResetUserMintsANewUserAndBlanksTheUserAndVisitScopedFields() {
        signedInUser()
        let oldUserId = storage.userId
        let oldSession = storage.sessionId

        storage.resetUser()

        XCTAssertNotEqual(storage.userId, oldUserId)
        XCTAssertNil(storage.suid)
        XCTAssertNotEqual(storage.sessionId, oldSession)
        XCTAssertTrue(storage.userVars.isEmpty)
        XCTAssertTrue(storage.userSegments.isEmpty)
        XCTAssertTrue(storage.sessionVars.isEmpty)
        XCTAssertNil(storage.landingPage)
        XCTAssertNil(storage.previousVisit)
    }

    func testResetUserWipesTheCdpIdentityButKeepsTheCmpConsent() {
        signedInUser()
        storage.resetUser()
        XCTAssertNil(storage.readCdpMasterId())
        XCTAssertNil(storage.readCdpCachedIdentity(sessionId: storage.sessionId))
        XCTAssertEqual(storage.hasConsent, true)
    }

    func testClearCdpCachedIdentityReadsBackAsAbsent() {
        let session = storage.sessionId
        storage.writeCdpCachedIdentity(rfv: CdpRfv(rfv: 1, r: 1, f: 1, v: 1), cohorts: [1], sessionId: session)
        storage.clearCdpCachedIdentity()
        XCTAssertNil(storage.readCdpCachedIdentity(sessionId: session))
        _ = storage.writeCdpMasterId(UUID_A)
        storage.clearCdpMasterId()
        XCTAssertNil(storage.readCdpMasterId())
    }

    func testRemoveUserVarDropsOnlyTheNamedVar() {
        storage.addUserVar(name: "a", value: "1")
        storage.addUserVar(name: "b", value: "2")
        storage.removeUserVar(name: "a")
        storage.removeUserVar(name: "ghost")
        XCTAssertEqual(storage.userVars, ["b": "2"])
    }

    /// The tracker's wiring order: CDP wipe first (it needs the live master), then storage.
    func testTheCdpWipeTargetsTheBucketsOfTheLivePreviousMaster() {
        signedInUser()
        let env = CdpTestEnv()
        env.segmentsStore.write(account: env.account, masterId: UUID_A, value: ["mine"])
        env.serverSegmentsStore.write(account: env.account, masterId: UUID_A, value: ["srv"])
        env.segmentsStore.setActiveMid(account: env.account, masterId: "stale-mid")

        UserRotation(
            clearCdpIdentity: { [self] in
                env.host.masterId = storage.readCdpMasterId()
                env.manager.clearIdentity()
                storage.clearCdpMasterId()
            },
            resetStorage: { [self] in storage.resetUser() },
            rebootstrapTrackInfo: {}
        ).rotate()

        XCTAssertEqual(env.clearedBuckets.first?.1, UUID_A)
        XCTAssertEqual(env.segmentsStore.read(account: env.account, masterId: UUID_A), [])
        XCTAssertNil(env.serverSegmentsStore.read(account: env.account, masterId: UUID_A))
        XCTAssertEqual(env.segmentsStore.getActiveMid(account: env.account), LOCAL_MID_SENTINEL)
        XCTAssertNil(storage.readCdpMasterId())
        XCTAssertEqual(env.api.resolveParams.count, 0)
    }
}

final class CdpBeaconTests: XCTestCase {
    func testCdpFreshIsEncodedOnlyWhenSet() {
        var info = IngestTrackInfo()
        info.cdpMasterId = UUID_A
        info.cdpFresh = "1"
        var json = info.jsonEncode()!
        XCTAssertEqual(json["cdp_fresh"] as? String, "1")
        XCTAssertEqual(json["cdp_mid"] as? String, UUID_A)

        info.cdpFresh = nil
        json = info.jsonEncode()!
        XCTAssertNil(json["cdp_fresh"])
    }
}

/// The public surface is **add-only**: every name here is reachable from host apps, so
/// renaming or removing one breaks them silently. Editing this list is the agreed moment
/// to check who is already calling the old name.
final class CdpPublicSurfaceTests: XCTestCase {
    func testEveryNameOnCdpTrackingStaysPut() {
        let cdp: CdpTracking = CdpTracker.shared
        // Referencing each member is the compile-time pin; the assertions keep the test meaningful.
        _ = cdp.setIdentity(type:value:isDeterministic:completion:)
        _ = cdp.deleteIdentity(type:value:completion:)
        _ = cdp.getMasterId
        _ = cdp.getUserProfile
        _ = cdp.trackConsent(_:completion:)
        _ = cdp.getConsent(_:completion:)
        _ = cdp.hasConsent(_:completion:)
        _ = cdp.normalizeEmail(_:)
        _ = cdp.normalizePhone(_:)
        _ = cdp.hashEmail(_:)
        _ = cdp.hashPhone(_:)
        _ = cdp.addCdpSegment(_:)
        _ = cdp.removeCdpSegment(_:)
        _ = cdp.setCdpSegments(_:)
        _ = cdp.clearCdpSegments
        _ = cdp.getCdpSegments
        _ = cdp.listServerSegments
        _ = cdp.getServerSegments(completion:)
        _ = cdp.listServerProperties
        _ = cdp.getServerProperties(completion:)
        _ = cdp.getMeterSnapshot(completion:)
        _ = cdp.getMeter(_:)
        _ = cdp.listMeters
        _ = cdp.incrementMeter(_:completion:)
        XCTAssertNotNil(cdp.identityTypes)
    }

    func testEveryCdpAdjacentNameOnCompassTrackingStaysPut() {
        let tracker: CompassTracking = CompassTracker.shared
        _ = tracker.resetUser(completion:)
        _ = tracker.getUserSegments as () -> [String]
        _ = tracker.getUserSegments(completion:)
        _ = tracker.getUserVars as () -> [String: String]
        _ = tracker.getUserVars(completion:)
        _ = tracker.setSiteUserId(_:)
        _ = tracker.setUserVar(name:value:)
        _ = tracker.addUserSegment(_:)
        _ = tracker.setUserSegments(_:)
        _ = tracker.removeUserSegment(_:)
        _ = tracker.clearUserSegments
        _ = tracker.setConsent(_:)
        XCTAssertNotNil(tracker.getUserId())
    }
}
