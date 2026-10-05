//
//  CdpSegmentsAndStoresTests.swift
//  CompassSDKTests
//
//  Segment ownership + the 100 cap, the merged user-data views, hashing, identity
//  types, the new mirror stores and the consent memory.
//

import XCTest
@testable import CompassSDK

final class SegmentOwnershipTests: XCTestCase {
    private let hundred = (1...100).map { "s\($0)" }

    func testMergeSegmentsUnionsServerFirstDedupesAndTolerateNil() {
        XCTAssertEqual(SegmentOwnership.mergeSegments(owned: ["device"], server: ["server"]), ["server", "device"])
        XCTAssertEqual(SegmentOwnership.mergeSegments(owned: ["both", "only-device"], server: ["both"]), ["both", "only-device"])
        XCTAssertEqual(SegmentOwnership.mergeSegments(owned: nil, server: ["a"]), ["a"])
        XCTAssertEqual(SegmentOwnership.mergeSegments(owned: ["a"], server: nil), ["a"])
        XCTAssertEqual(SegmentOwnership.mergeSegments(owned: nil, server: nil), [])
    }

    func testMergeSegmentsDoesNotTrim() {
        XCTAssertEqual(SegmentOwnership.mergeSegments(owned: ["device"], server: hundred + ["s101", "s102", "s103", "s104", "s105"]).count, 106)
    }

    func testRejectUnownedSegments() {
        XCTAssertEqual(SegmentOwnership.rejectUnownedSegments(requested: ["mine", "server-only"], owned: ["mine"], server: ["server-only"]), ["mine"])
        XCTAssertEqual(SegmentOwnership.rejectUnownedSegments(requested: ["both"], owned: ["both"], server: ["both"]), ["both"])
        XCTAssertEqual(SegmentOwnership.rejectUnownedSegments(requested: ["a", "b"], owned: [], server: []), ["a", "b"])
        XCTAssertEqual(SegmentOwnership.rejectUnownedSegments(requested: ["a", "b"], owned: nil, server: nil), ["a", "b"])
    }

    func testLimitAndTrim() {
        XCTAssertFalse(SegmentOwnership.isOverSegmentLimit(hundred))
        XCTAssertTrue(SegmentOwnership.isOverSegmentLimit(hundred + ["s101"]))
        XCTAssertEqual(SegmentOwnership.trimSegments(hundred + ["s101", "s102"]), hundred)
        XCTAssertEqual(SegmentOwnership.trimSegments(["a"]), ["a"])
    }

    func testMergeVars() {
        XCTAssertEqual(SegmentOwnership.mergeVars(owned: ["plan": "premium"], server: ["email": "user@site.com"]), ["plan": "premium", "email": "user@site.com"])
        XCTAssertEqual(SegmentOwnership.mergeVars(owned: ["email": "device@site.com"], server: ["email": "crm@site.com"]), ["email": "device@site.com"])
        XCTAssertEqual(SegmentOwnership.mergeVars(owned: ["a": "1"], server: nil), ["a": "1"])
        XCTAssertEqual(SegmentOwnership.mergeVars(owned: nil, server: ["b": "2"]), ["b": "2"])
    }
}

final class SegmentTrimmerTests: XCTestCase {
    private var vars: [String: String] = [:]
    private var setCalls: [(String, String)] = []
    private var removeCalls: [String] = []
    private lazy var trimmer = SegmentTrimmer(
        readOwnedUserVars: { [unowned self] in self.vars },
        setUserVar: { [unowned self] name, value in self.vars[name] = value; self.setCalls.append((name, value)) },
        removeUserVar: { [unowned self] name in self.vars.removeValue(forKey: name); self.removeCalls.append(name) }
    )
    private let hundredServer = (1...100).map { "srv\($0)" }

    func testOverflowDropsTheDeviceSegmentAndSetsTheFlagOnce() {
        let out = trimmer.trim(SegmentOwnership.mergeSegments(owned: ["device"], server: hundredServer))
        XCTAssertEqual(out, hundredServer)
        XCTAssertEqual(setCalls.count, 1)
        XCTAssertEqual(setCalls.first?.0, MRF_TOO_MANY_SEGMENTS)
        XCTAssertEqual(setCalls.first?.1, "true")

        _ = trimmer.trim(hundredServer + ["device"])
        XCTAssertEqual(setCalls.count, 1)
    }

    func testFitsDoesNotFlagAndFlaggedFitsAgainUnflags() {
        _ = trimmer.trim(["a", "b"])
        XCTAssertTrue(setCalls.isEmpty)
        vars[MRF_TOO_MANY_SEGMENTS] = "true"
        _ = trimmer.trim(["a"])
        XCTAssertEqual(removeCalls, [MRF_TOO_MANY_SEGMENTS])
        XCTAssertNil(vars[MRF_TOO_MANY_SEGMENTS])
    }

    func testExactlyOneHundredIsNotOver() {
        XCTAssertEqual(trimmer.trim(hundredServer), hundredServer)
        XCTAssertTrue(setCalls.isEmpty)
    }
}

final class UserDataMergerTests: XCTestCase {
    private var env: CdpTestEnv!
    private var cdpEnabled = true
    private var ownedSegments: [String] = []
    private var ownedVars: [String: String] = [:]
    private var merger: UserDataMerger!
    private let hundredServer = (1...100).map { "srv\($0)" }

    override func setUp() {
        super.setUp()
        env = CdpTestEnv()
        cdpEnabled = true
        ownedSegments = []
        ownedVars = [:]
        merger = UserDataMerger(
            cdpEnabled: { [unowned self] in self.cdpEnabled },
            readOwnedSegments: { [unowned self] in self.ownedSegments },
            readOwnedVars: { [unowned self] in self.ownedVars },
            listServerSegments: { [unowned self] in self.env.manager.serverSegments },
            getServerSegments: { [unowned self] completion in self.env.manager.getServerSegments(completion: completion) },
            listServerProperties: { [unowned self] in self.env.manager.serverProperties },
            getServerProperties: { [unowned self] completion in self.env.manager.getServerProperties(completion: completion) },
            trimmer: SegmentTrimmer(
                readOwnedUserVars: { [unowned self] in self.ownedVars },
                setUserVar: { [unowned self] name, value in self.ownedVars[name] = value },
                removeUserVar: { [unowned self] name in self.ownedVars.removeValue(forKey: name) }
            )
        )
    }

    override func tearDown() {
        env = nil
        super.tearDown()
    }

    private func serverHas(_ segments: [String], properties: [String: String] = [:]) {
        env.host.masterId = UUID_A
        env.manager.syncServerSegments(segments)
        env.manager.syncServerProperties(properties)
    }

    func testSegmentsMergeServerAheadOfDeviceAndDedupe() {
        ownedSegments = ["device", "both"]
        serverHas(["both", "server"])
        XCTAssertEqual(merger.segments(), ["both", "server", "device"])
    }

    func testOverflowDropsTheDeviceSegmentSetsTheFlagAndClearsItWhenItFits() {
        ownedSegments = ["device"]
        serverHas(hundredServer)
        XCTAssertEqual(merger.segments(), hundredServer)
        XCTAssertEqual(ownedVars[MRF_TOO_MANY_SEGMENTS], "true")

        ownedVars[MRF_TOO_MANY_SEGMENTS] = "sentinel"
        _ = merger.segments()
        XCTAssertEqual(ownedVars[MRF_TOO_MANY_SEGMENTS], "sentinel")

        serverHas(Array(hundredServer.prefix(10)))
        _ = merger.segments()
        XCTAssertNil(ownedVars[MRF_TOO_MANY_SEGMENTS])
    }

    func testTheTrimNeverTouchesTheStores() {
        ownedSegments = ["device"]
        serverHas(hundredServer)
        _ = merger.segments()
        XCTAssertEqual(ownedSegments, ["device"])
        XCTAssertEqual(env.manager.serverSegments, hundredServer)
    }

    func testAsyncSegmentsResolveFirstAndApplyTheSameTrim() {
        ownedSegments = ["device"]
        env.api.resolveResponses = [CdpIdentityResponse(masterId: UUID_A, rfv: nil, cohorts: [], segments: hundredServer)]
        var out: [String] = []
        waitFor { done in self.merger.segments { out = $0; done() } }
        XCTAssertEqual(env.api.resolveParams.count, 1)
        XCTAssertEqual(out, hundredServer)
        XCTAssertEqual(ownedVars[MRF_TOO_MANY_SEGMENTS], "true")
    }

    func testDisabledIgnoresTheServerSideButStillCaps() {
        cdpEnabled = false
        serverHas(["server"])
        ownedSegments = (1...101).map { "d\($0)" }
        let out = merger.segments()
        XCTAssertEqual(out.count, 100)
        XCTAssertFalse(out.contains("server"))
        XCTAssertEqual(ownedVars[MRF_TOO_MANY_SEGMENTS], "true")
    }

    func testVarsAppendServerPropertiesDeviceOwnedWins() {
        ownedVars = ["email": "device@site.com", "plan": "premium"]
        serverHas([], properties: ["email": "crm@site.com", "role": "editor"])
        XCTAssertEqual(merger.vars(), ["email": "device@site.com", "plan": "premium", "role": "editor"])

        env.api.resolveResponses = [CdpIdentityResponse(masterId: UUID_A, rfv: nil, cohorts: [], properties: ["role": "editor"])]
        var async: [String: String] = [:]
        waitFor { done in self.merger.vars { async = $0; done() } }
        XCTAssertEqual(env.api.resolveParams.count, 1)
        XCTAssertEqual(async, ["email": "device@site.com", "plan": "premium", "role": "editor"])

        cdpEnabled = false
        XCTAssertEqual(merger.vars(), ["email": "device@site.com", "plan": "premium"])
    }
}

final class CdpHashTests: XCTestCase {
    private let fooBar = "0c7e6a405862e402eb76a70f8a26fc732d07c32931e9fae9ab1582911d2e8a3b"
    private let phone = "cb24629d1dbeb6ee24e7c20610896274e8102e67aa6efc2f3a1be2893c38008b"

    func testNormalisation() {
        XCTAssertEqual(CdpHash.normalizeEmail("  Foo@BAR.com "), "foo@bar.com")
        XCTAssertEqual(CdpHash.normalizePhone(" +34600111222 "), "+34600111222")
        XCTAssertEqual(CdpHash.normalizePhone("ABC"), "ABC")
    }

    func testKnownDigests() {
        XCTAssertEqual(CdpHash.hashEmail(" Foo@Bar.com "), fooBar)
        XCTAssertEqual(CdpHash.hashEmail("FOO@BAR.COM"), CdpHash.hashEmail("foo@bar.com"))
        XCTAssertEqual(CdpHash.hashPhone(" +34600111222"), phone)
        XCTAssertNotEqual(CdpHash.hashPhone("+34600111222"), CdpHash.hashPhone("600111222"))
        XCTAssertEqual(fooBar.count, 64)
    }

    func testConsentEmailIdentityHashesUnderEmailSha256() {
        let subject = consentEmailIdentity(" Foo@Bar.com ")
        XCTAssertEqual(subject.idType, CdpIdentityTypes.emailSha256)
        XCTAssertEqual(subject.idValue, fooBar)
    }

    func testIdentityTypesSplitAndNoPhantoms() {
        XCTAssertTrue(CdpIdentityTypes.stable.contains(CdpIdentityTypes.emailSha256))
        XCTAssertTrue(CdpIdentityTypes.stable.contains(CdpIdentityTypes.registeredUserId))
        XCTAssertTrue(CdpIdentityTypes.deviceBound.contains(CdpIdentityTypes.crmId))
        XCTAssertEqual(CdpIdentityTypes.stable.count + CdpIdentityTypes.deviceBound.count, 16)
        let all = CdpIdentityTypes.stable.union(CdpIdentityTypes.deviceBound)
        XCTAssertFalse(all.contains("email_hash"))
        XCTAssertFalse(all.contains("phone_hash"))
    }

    func testThePublicSurfaceDelegatesTheHelpers() {
        let cdp: CdpTracking = CdpTracker.shared
        XCTAssertEqual(cdp.hashEmail("Foo@Bar.com"), fooBar)
        XCTAssertEqual(cdp.hashPhone("+34600111222"), phone)
        XCTAssertEqual(cdp.normalizeEmail(" Foo@Bar.com"), "foo@bar.com")
        XCTAssertEqual(cdp.normalizePhone(" +1 "), "+1")
        XCTAssertTrue(cdp.identityTypes == CdpIdentityTypes.self)
    }
}

final class CdpNewStoresTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "CdpNewStoresTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testServerSegmentsStoreMissIsNilDistinctFromEmpty() {
        let store = CdpServerSegmentsStore(defaults: defaults)
        XCTAssertNil(store.read(account: "acc", masterId: "mid"))
        store.write(account: "acc", masterId: "mid", value: [])
        XCTAssertEqual(store.read(account: "acc", masterId: "mid"), [])
        store.write(account: "acc", masterId: "mid", value: ["a", "b"])
        XCTAssertEqual(store.read(account: "acc", masterId: "mid"), ["a", "b"])
        XCTAssertNotNil(defaults.dictionary(forKey: "cdpsrvsegs_mid_acc"))
        store.clear(account: "acc", masterId: "mid")
        XCTAssertNil(store.read(account: "acc", masterId: "mid"))
    }

    func testServerSegmentsCleanupNeverPurgesTheActiveMaster() {
        let store = CdpServerSegmentsStore(defaults: defaults)
        store.write(account: "acc", masterId: "active", value: ["a"])
        store.write(account: "acc", masterId: "other", value: ["b"])
        store.cleanupExpired(account: "acc", activeMasterId: "active")
        XCTAssertEqual(store.read(account: "acc", masterId: "active"), ["a"])
        XCTAssertEqual(store.read(account: "acc", masterId: "other"), ["b"])
    }

    func testServerPropertiesStoreMissIsNilAndCoercesOnRead() {
        let store = CdpServerPropertiesStore(defaults: defaults)
        XCTAssertNil(store.read(account: "acc", masterId: "mid"))
        store.write(account: "acc", masterId: "mid", value: [:])
        XCTAssertEqual(store.read(account: "acc", masterId: "mid"), [:])
        store.write(account: "acc", masterId: "mid", value: ["plan": "premium"])
        XCTAssertEqual(store.read(account: "acc", masterId: "mid"), ["plan": "premium"])

        defaults.set(["properties": ["age": 42, "vip": true], "ts": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000))], forKey: "cdpsrvprops_mid_acc")
        XCTAssertEqual(store.read(account: "acc", masterId: "mid"), ["age": "42", "vip": "true"])
        store.clear(account: "acc", masterId: "mid")
        XCTAssertNil(store.read(account: "acc", masterId: "mid"))
    }

    func testConsentMemoryStore() {
        let store = CdpConsentMemoryStore(defaults: defaults)
        let accepted3 = CdpRememberedConsentDecision(versionId: "3", status: .accepted, ts: 10)
        let rejected1 = CdpRememberedConsentDecision(versionId: "1", status: .rejected, ts: 20)

        XCTAssertTrue(store.getRemembered(account: "acc").isEmpty)
        store.remember(account: "acc", consentId: "privacy", decision: accepted3)
        XCTAssertNotNil(defaults.dictionary(forKey: "cdpconsents_local_acc"))
        XCTAssertEqual(store.getRemembered(account: "acc")["privacy"], accepted3)
        XCTAssertTrue(store.getRemembered(account: "other").isEmpty)

        store.remember(account: "acc", consentId: "newsletter", decision: rejected1)
        XCTAssertEqual(Set(store.getRemembered(account: "acc").keys), ["privacy", "newsletter"])
        store.remember(account: "acc", consentId: "privacy", decision: rejected1)
        XCTAssertEqual(store.getRemembered(account: "acc")["privacy"], rejected1)

        store.forget(account: "acc", consentIds: ["privacy"])
        XCTAssertEqual(Array(store.getRemembered(account: "acc").keys), ["newsletter"])
        let before = defaults.dictionary(forKey: "cdpconsents_local_acc")?["ts"] as? NSNumber
        store.forget(account: "acc", consentIds: ["ghost"])
        XCTAssertEqual(defaults.dictionary(forKey: "cdpconsents_local_acc")?["ts"] as? NSNumber, before)
        store.forget(account: "acc", consentIds: ["newsletter"])
        XCTAssertNil(defaults.dictionary(forKey: "cdpconsents_local_acc"))

        store.remember(account: "acc", consentId: "privacy", decision: accepted3)
        store.clear(account: "acc")
        XCTAssertTrue(store.getRemembered(account: "acc").isEmpty)

        defaults.set(["decisions": ["p": ["versionId": "2", "status": "accept", "ts": 5]], "ts": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000))], forKey: "cdpconsents_local_acc")
        XCTAssertEqual(store.getRemembered(account: "acc")["p"]?.status, .accepted)
    }
}
