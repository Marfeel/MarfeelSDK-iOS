//
//  CdpManagerIdentityTests.swift
//  CompassSDKTests
//
//  Identity resolution, Server Segments / Properties mirrors, identityFresh,
//  deleteIdentity, clearIdentity and the reset staleness guard.
//

import XCTest
@testable import CompassSDK

final class CdpManagerIdentityTests: XCTestCase {
    private var env: CdpTestEnv!
    private var manager: CdpManager { env.manager }
    private var api: MockCdpApi { env.api }
    private var host: MockCdpHost { env.host }

    override func setUp() {
        super.setUp()
        env = CdpTestEnv()
    }

    override func tearDown() {
        env = nil
        super.tearDown()
    }

    private func identity(_ masterId: String?, segments: [String]? = nil, properties: [String: String]? = nil, rfv: CdpRfv? = nil, cohorts: [Int] = []) -> CdpIdentityResponse {
        return CdpIdentityResponse(masterId: masterId, rfv: rfv, cohorts: cohorts, segments: segments, properties: properties)
    }

    // MARK: - resolve

    func testResolveMemoizesWithinASession() {
        api.resolveResponses = [identity(UUID_A)]
        manager.resolveAndWait(self)
        manager.resolveAndWait(self)
        XCTAssertEqual(api.resolveParams.count, 1)
    }

    func testResolveSkipsNetworkWhenIdentityAndBothMirrorsAreKnown() {
        env.warmVisitor()
        manager.resolveAndWait(self)
        XCTAssertEqual(api.resolveParams.count, 0)
    }

    func testResolveGuardResolvesWhenTheServerSegmentMirrorHasNoEntry() {
        host.masterId = UUID_A
        host.cached = CdpCachedIdentity(rfv: nil, cohorts: [])
        host.cachedSession = host.cdpSessionId
        env.serverPropertiesStore.write(account: env.account, masterId: UUID_A, value: [:])
        api.resolveResponses = [identity(UUID_A, segments: [])]

        manager.resolveAndWait(self)

        XCTAssertEqual(api.resolveParams.count, 1)
    }

    func testResolveGuardReResolvesWhenThePropertiesMirrorIsAMiss() {
        host.masterId = UUID_A
        host.cached = CdpCachedIdentity(rfv: nil, cohorts: [])
        host.cachedSession = host.cdpSessionId
        env.serverSegmentsStore.write(account: env.account, masterId: UUID_A, value: ["s"])
        api.resolveResponses = [identity(UUID_A)]

        manager.resolveAndWait(self)

        XCTAssertEqual(api.resolveParams.count, 1)
    }

    func testResolveGuardCacheHitCommitsTheStoredMirrors() {
        env.warmVisitor(segments: ["lv_a_user_CC_LV"], properties: ["plan": "premium"])
        manager.resolveAndWait(self)
        XCTAssertEqual(manager.serverSegments, ["lv_a_user_CC_LV"])
        XCTAssertEqual(manager.serverProperties, ["plan": "premium"])
    }

    func testResolveRetriesOnFailure() {
        api.resolveResponses = [UNKNOWN_CDP_IDENTITY, UNKNOWN_CDP_IDENTITY]
        manager.resolveAndWait(self)
        manager.resolveAndWait(self)
        XCTAssertEqual(api.resolveParams.count, 2)
    }

    func testSessionRotationClearsTheMemo() {
        api.resolveResponses = [identity(UUID_A), identity(UUID_A)]
        manager.resolveAndWait(self)
        host.cdpSessionId = "session-2"
        manager.resolveAndWait(self)
        XCTAssertEqual(api.resolveParams.count, 2)
    }

    func testNoNetworkWithoutConsent() {
        host.cdpConsent = false
        manager.resolveAndWait(self)
        XCTAssertEqual(api.resolveParams.count, 0)
    }

    func testResolveCompletionIsDeliveredEvenWithoutConsent() {
        host.cdpConsent = false
        waitFor { done in self.manager.resolveIdentity(completion: done) }
    }

    func testUpdateStateCachesRfvAndCohortsEvenWithoutAMaster() {
        api.resolveResponses = [identity(nil, rfv: CdpRfv(rfv: 9, r: 1, f: 2, v: 3), cohorts: [5, 6])]
        manager.resolveAndWait(self)
        XCTAssertNil(host.masterId)
        XCTAssertEqual(host.cached?.rfv?.rfv, 9)
        XCTAssertEqual(host.cached?.cohorts, [5, 6])
    }

    // MARK: - link

    func testLinkAwaitsResolveThenAdoptsTheReturnedMaster() {
        api.resolveResponses = [identity(UUID_A)]
        api.linkResponses = [identity(UUID_B)]

        waitFor { done in self.manager.linkIdentity(type: "registered_user_id", value: "u@x.com", isDeterministic: true, completion: done) }

        XCTAssertEqual(api.resolveParams.count, 1)
        XCTAssertEqual(api.linkParams.first?.idType, "registered_user_id")
        XCTAssertEqual(host.masterId, UUID_B)
    }

    // MARK: - identityFresh

    func testIdentityFreshStartsFalse() {
        XCTAssertFalse(manager.identityFresh)
        XCTAssertFalse(manager.getUserProfile().identityFresh)
    }

    func testIdentityFreshFlipsTrueAfterAResolveThatReturnedAMaster() {
        api.resolveResponses = [identity(UUID_A)]
        manager.resolveAndWait(self)
        XCTAssertTrue(manager.identityFresh)
        XCTAssertTrue(manager.getUserProfile().identityFresh)
    }

    func testIdentityFreshStaysFalseWhenTheResolveFailed() {
        api.resolveResponses = [UNKNOWN_CDP_IDENTITY]
        manager.resolveAndWait(self)
        XCTAssertFalse(manager.identityFresh)
    }

    func testIdentityFreshStaysFalseOnTheWarmPath() {
        env.warmVisitor()
        manager.resolveAndWait(self)
        XCTAssertFalse(manager.identityFresh)
    }

    func testIdentityFreshFlipsTrueAfterALink() {
        api.resolveResponses = [UNKNOWN_CDP_IDENTITY]
        api.linkResponses = [identity(UUID_A)]
        waitFor { done in self.manager.linkIdentity(type: "email", value: "u@x.com", isDeterministic: true, completion: done) }
        XCTAssertTrue(manager.identityFresh)
    }

    func testIdentityFreshIsDroppedByClearIdentity() {
        api.resolveResponses = [identity(UUID_A)]
        manager.resolveAndWait(self)
        manager.clearIdentity()
        XCTAssertFalse(manager.identityFresh)
    }

    // MARK: - server segments

    func testSyncServerSegmentsStoresServerMinusDeviceOwned() {
        host.masterId = UUID_A
        host.legacySegments = ["evolok:Device_mobile"]

        manager.syncServerSegments(["evolok:Device_mobile", "lv_a_user_CC_LV", "is_deterministic"])

        XCTAssertEqual(manager.serverSegments, ["lv_a_user_CC_LV", "is_deterministic"])
        XCTAssertEqual(env.serverSegmentsStore.read(account: env.account, masterId: UUID_A), ["lv_a_user_CC_LV", "is_deterministic"])
    }

    func testSyncServerSegmentsTreatsCdpsegsEntriesAsDeviceOwned() {
        host.masterId = UUID_A
        env.segmentsStore.write(account: env.account, masterId: UUID_A, value: ["lv_a_user_CC_LV"])
        manager.syncServerSegments(["lv_a_user_CC_LV", "is_deterministic"])
        XCTAssertEqual(manager.serverSegments, ["is_deterministic"])
    }

    func testSyncServerSegmentsTreatsAMissingFieldAsEmpty() {
        host.masterId = UUID_A
        manager.syncServerSegments(nil)
        XCTAssertEqual(manager.serverSegments, [])
        XCTAssertEqual(env.serverSegmentsStore.read(account: env.account, masterId: UUID_A), [])
    }

    func testSyncServerSegmentsNoOpsWithoutAMaster() {
        manager.syncServerSegments(["lv_a_user_CC_LV"])
        XCTAssertEqual(manager.serverSegments, [])
        XCTAssertNil(env.serverSegmentsStore.read(account: env.account, masterId: LOCAL_MID_SENTINEL))
    }

    func testAResolvePersistsTheSegmentsFromTheResponse() {
        api.resolveResponses = [identity(UUID_A, segments: ["srv"])]
        manager.resolveAndWait(self)
        XCTAssertEqual(manager.serverSegments, ["srv"])
        XCTAssertEqual(env.serverSegmentsStore.read(account: env.account, masterId: UUID_A), ["srv"])
    }

    func testRemoveSegmentPrunesTheServerDiff() {
        host.masterId = UUID_A
        manager.syncServerSegments(["lv_a_user_CC_LV", "is_deterministic"])
        manager.removeSegment("lv_a_user_CC_LV")
        manager.drainQueueForTesting()
        XCTAssertEqual(manager.serverSegments, ["is_deterministic"])
        XCTAssertEqual(env.serverSegmentsStore.read(account: env.account, masterId: UUID_A), ["is_deterministic"])
    }

    func testClearSegmentsEmptiesTheServerDiffEvenWhenNothingIsLocallyOwned() {
        host.masterId = UUID_A
        manager.syncServerSegments(["lv_a_user_CC_LV"])
        manager.clearSegments()
        manager.drainQueueForTesting()
        XCTAssertEqual(manager.serverSegments, [])
        XCTAssertEqual(api.updateParams.count, 0)
    }

    func testServerSegmentsAreDroppedNeverCarriedOverOnAMasterChange() {
        api.resolveResponses = [identity(UUID_A, segments: ["old-srv"])]
        manager.resolveAndWait(self)
        api.linkResponses = [identity(UUID_B, segments: ["new-srv"])]

        waitFor { done in self.manager.linkIdentity(type: "email", value: "u@x.com", isDeterministic: true, completion: done) }

        XCTAssertNil(env.serverSegmentsStore.read(account: env.account, masterId: UUID_A))
        XCTAssertEqual(env.serverSegmentsStore.read(account: env.account, masterId: UUID_B), ["new-srv"])
        XCTAssertEqual(manager.serverSegments, ["new-srv"])
    }

    func testGetServerSegmentsResolvesFirst() {
        api.resolveResponses = [identity(UUID_A, segments: ["srv"])]
        var received: [String] = []
        waitFor { done in self.manager.getServerSegments { received = $0; done() } }
        XCTAssertEqual(received, ["srv"])
        XCTAssertEqual(api.resolveParams.count, 1)
    }

    // MARK: - server properties

    func testSyncServerPropertiesMirrorsTheWholeMap() {
        host.masterId = UUID_A
        manager.syncServerProperties(["plan": "premium", "geo_city": "Barcelona"])
        XCTAssertEqual(manager.serverProperties, ["plan": "premium", "geo_city": "Barcelona"])
        XCTAssertEqual(env.serverPropertiesStore.read(account: env.account, masterId: UUID_A), ["plan": "premium", "geo_city": "Barcelona"])
    }

    func testSyncServerPropertiesTreatsAMissingFieldAsEmptyAndNoOpsWithoutAMaster() {
        manager.syncServerProperties(["a": "b"])
        XCTAssertEqual(manager.serverProperties, [:])
        host.masterId = UUID_A
        manager.syncServerProperties(nil)
        XCTAssertEqual(env.serverPropertiesStore.read(account: env.account, masterId: UUID_A), [:])
    }

    func testALinkPersistsThePropertiesFromTheResponse() {
        api.resolveResponses = [UNKNOWN_CDP_IDENTITY]
        api.linkResponses = [identity(UUID_A, properties: ["role": "editor"])]
        waitFor { done in self.manager.linkIdentity(type: "email", value: "u@x.com", isDeterministic: true, completion: done) }
        XCTAssertEqual(env.serverPropertiesStore.read(account: env.account, masterId: UUID_A), ["role": "editor"])
    }

    func testServerPropertiesAreDroppedOnAMasterChangeAndKeptWhenUnchanged() {
        api.resolveResponses = [identity(UUID_A, properties: ["a": "1"])]
        manager.resolveAndWait(self)
        api.updateResponses = [identity(UUID_A)]
        waitFor { done in self.manager.updateProfile(["k": "v"], completion: done) }
        XCTAssertEqual(env.serverPropertiesStore.read(account: env.account, masterId: UUID_A), ["a": "1"])

        api.linkResponses = [identity(UUID_B)]
        waitFor { done in self.manager.linkIdentity(type: "email", value: "u@x.com", isDeterministic: true, completion: done) }
        XCTAssertNil(env.serverPropertiesStore.read(account: env.account, masterId: UUID_A))
    }

    // MARK: - deleteIdentity

    func testDeleteIdentityPostsUnderTheMasterAndRefreshesTheMirrors() {
        env.warmVisitor()
        api.deleteResponses = [CdpDeleteResponse(identity: identity(UUID_A, segments: ["left"], properties: ["p": "q"], rfv: CdpRfv(rfv: 2, r: 2, f: 2, v: 2), cohorts: [9]), deleted: 1)]

        waitFor { done in self.manager.deleteIdentity(type: "email", value: "u@x.com", completion: done) }

        let params = api.deleteParams.first
        XCTAssertEqual(params?.siteId, 456)
        XCTAssertEqual(params?.masterId, UUID_A)
        XCTAssertEqual(params?.idType, "email")
        XCTAssertEqual(params?.idValue, "u@x.com")
        XCTAssertEqual(manager.serverSegments, ["left"])
        XCTAssertEqual(manager.serverProperties, ["p": "q"])
        XCTAssertEqual(host.cached?.rfv?.rfv, 2)
    }

    func testDeleteIdentityOmitsTheValueWhenNoneIsGiven() {
        env.warmVisitor()
        api.deleteResponses = [CdpDeleteResponse(identity: identity(UUID_A), deleted: 3)]
        waitFor { done in self.manager.deleteIdentity(type: "crm_id", value: nil, completion: done) }
        XCTAssertNil(api.deleteParams.first?.idValue)
    }

    func testDeleteIdentitySkipsWithoutConsentOrMaster() {
        host.cdpConsent = false
        host.masterId = UUID_A
        waitFor { done in self.manager.deleteIdentity(type: "email", value: "x", completion: done) }
        XCTAssertEqual(api.deleteParams.count, 0)

        host.cdpConsent = true
        host.masterId = nil
        api.resolveResponses = [UNKNOWN_CDP_IDENTITY]
        waitFor { done in self.manager.deleteIdentity(type: "email", value: "x", completion: done) }
        XCTAssertEqual(api.deleteParams.count, 0)
    }

    func testDeleteIdentityDoesNotMarkTheIdentityFreshAndLeavesStateAloneOnFailure() {
        env.warmVisitor(segments: ["keep"])
        manager.resolveAndWait(self)
        api.deleteResponses = [nil]
        waitFor { done in self.manager.deleteIdentity(type: "email", value: "x", completion: done) }
        XCTAssertFalse(manager.identityFresh)
        XCTAssertEqual(manager.serverSegments, ["keep"])
        XCTAssertEqual(host.cached?.rfv?.rfv, 1)
    }

    // MARK: - clearIdentity

    func testClearIdentityWipesTheMasterTheCacheAndTheMirrors() {
        api.resolveResponses = [identity(UUID_A, segments: ["srv"], properties: ["a": "b"], rfv: CdpRfv(rfv: 1, r: 1, f: 1, v: 1), cohorts: [1])]
        manager.resolveAndWait(self)

        manager.clearIdentity()

        XCTAssertNil(host.masterId)
        XCTAssertNil(host.cached)
        XCTAssertEqual(manager.serverSegments, [])
        XCTAssertEqual(manager.serverProperties, [:])
        XCTAssertNil(manager.getUserProfile().masterId)
    }

    func testClearIdentityClearsTheMidScopedStorageOfThePreviousMasterAndResetsThePointer() {
        host.masterId = UUID_A
        env.segmentsStore.write(account: env.account, masterId: UUID_A, value: ["mine"])
        env.segmentsStore.setActiveMid(account: env.account, masterId: UUID_A)
        env.serverSegmentsStore.write(account: env.account, masterId: UUID_A, value: ["srv"])
        env.serverPropertiesStore.write(account: env.account, masterId: UUID_A, value: ["a": "b"])
        env.consentMemory.remember(account: env.account, consentId: "privacy", decision: CdpRememberedConsentDecision(versionId: "1", status: .accepted, ts: 1))

        manager.clearIdentity()

        XCTAssertEqual(env.segmentsStore.read(account: env.account, masterId: UUID_A), [])
        XCTAssertNil(env.serverSegmentsStore.read(account: env.account, masterId: UUID_A))
        XCTAssertNil(env.serverPropertiesStore.read(account: env.account, masterId: UUID_A))
        XCTAssertTrue(env.consentMemory.getRemembered(account: env.account).isEmpty)
        XCTAssertEqual(env.segmentsStore.getActiveMid(account: env.account), LOCAL_MID_SENTINEL)
        XCTAssertEqual(env.clearedBuckets.count, 1)
        XCTAssertEqual(env.clearedBuckets.first?.1, UUID_A)
    }

    func testClearIdentityFallsBackToThePointerThenTheSentinel() {
        env.segmentsStore.setActiveMid(account: env.account, masterId: UUID_B)
        manager.clearIdentity()
        XCTAssertEqual(env.clearedBuckets.last?.1, UUID_B)
        manager.clearIdentity()
        XCTAssertEqual(env.clearedBuckets.last?.1, LOCAL_MID_SENTINEL)
    }

    func testClearIdentityDropsTheResolveMemoSoTheNextVisitorMintsAFreshMaster() {
        api.resolveResponses = [identity(UUID_A), identity(UUID_B)]
        manager.resolveAndWait(self)
        manager.clearIdentity()
        manager.resolveAndWait(self)
        XCTAssertEqual(api.resolveParams.count, 2)
        XCTAssertEqual(host.masterId, UUID_B)
    }

    func testClearIdentityReArmsTheOneShot() {
        var fires = 0
        manager.onIdentityResolved { fires += 1 }
        api.resolveResponses = [identity(UUID_A), identity(UUID_A)]
        manager.resolveAndWait(self)
        XCTAssertEqual(fires, 1)
        manager.clearIdentity()
        manager.resolveAndWait(self)
        XCTAssertEqual(fires, 2)
    }

    func testClearIdentityNeverTouchesTheNetwork() {
        host.masterId = UUID_A
        manager.clearIdentity()
        settle(0.05)
        XCTAssertEqual(api.resolveParams.count, 0)
        XCTAssertEqual(api.resetSiteIds.count, 0)
    }

    func testAResolveThatStartedBeforeClearIdentityDoesNotResurrectTheOldMaster() {
        var release: ((CdpIdentityResponse) -> Void)?
        let held = XCTestExpectation(description: "held")
        api.holdResolve = { completion in release = completion; held.fulfill() }
        let resolved = XCTestExpectation(description: "resolved")
        manager.resolveIdentity { resolved.fulfill() }
        wait(for: [held], timeout: 2)

        manager.clearIdentity()
        release?(identity(UUID_A))
        wait(for: [resolved], timeout: 2)

        XCTAssertNil(host.masterId)
        XCTAssertNil(host.cached)
    }

    func testAnUpdateThatStartedBeforeClearIdentityDoesNotResurrectTheOldMaster() {
        host.masterId = UUID_A
        var release: ((CdpIdentityResponse) -> Void)?
        let held = XCTestExpectation(description: "held")
        api.holdUpdate = { completion in release = completion; held.fulfill() }
        let updated = XCTestExpectation(description: "updated")
        manager.updateProfile(["plan": "gold"]) { updated.fulfill() }
        wait(for: [held], timeout: 2)

        manager.clearIdentity()
        release?(identity(UUID_A))
        wait(for: [updated], timeout: 2)

        XCTAssertNil(host.masterId)
        XCTAssertNil(host.cached)
        XCTAssertTrue(env.masterIdChanges.isEmpty)
    }

    func testASegmentChangeThatStartedBeforeClearIdentityDoesNotResurrectTheOldMaster() {
        host.masterId = UUID_A
        var release: ((CdpIdentityResponse) -> Void)?
        let held = XCTestExpectation(description: "held")
        api.holdUpdate = { completion in release = completion; held.fulfill() }
        manager.addSegment("sports")
        wait(for: [held], timeout: 2)

        manager.clearIdentity()
        release?(identity(UUID_A))
        settle()

        XCTAssertNil(host.masterId)
        XCTAssertEqual(env.segmentsStore.getActiveMid(account: env.account), LOCAL_MID_SENTINEL)
    }

    func testResetRemoteIdentityPostsTheSiteIdAndIsInertWhenDisabled() {
        api.resetResponses = [CdpResetResponse(reset: true, siteId: 456, cleared: [])]
        var result: CdpResetResponse?
        waitFor { done in self.manager.resetRemoteIdentity { result = $0; done() } }
        XCTAssertEqual(result?.reset, true)
        XCTAssertEqual(api.resetSiteIds, [456])

        host.cdpEnabled = false
        waitFor { done in self.manager.resetRemoteIdentity { result = $0; done() } }
        XCTAssertNil(result)
        XCTAssertEqual(api.resetSiteIds.count, 1)
    }

    // MARK: - profile / device segments

    func testUpdateProfileNoOpsWithoutAMasterAndPostsWithOne() {
        waitFor { done in self.manager.updateProfile(["k": "v"], completion: done) }
        XCTAssertEqual(api.updateParams.count, 0)

        host.masterId = UUID_A
        waitFor { done in self.manager.updateProfile(["timezone": "Europe/Madrid"], completion: done) }
        XCTAssertEqual(api.updateParams.first?.properties?["timezone"], "Europe/Madrid")
    }

    func testSegmentsAreWrittenLocallyFirstThenSynced() {
        host.masterId = UUID_A
        manager.addSegment("sports")
        manager.drainQueueForTesting()
        XCTAssertEqual(env.segmentsStore.read(account: env.account, masterId: UUID_A), ["sports"])
        XCTAssertEqual(api.updateParams.first?.segmentsAdd, ["sports"])
    }

    func testReplaceSegmentsDiffsAgainstThePreviousLocalSnapshot() {
        host.masterId = UUID_A
        env.segmentsStore.write(account: env.account, masterId: UUID_A, value: ["a", "b"])
        manager.replaceSegments(["b", "c", "c"])
        manager.drainQueueForTesting()
        XCTAssertEqual(env.segmentsStore.read(account: env.account, masterId: UUID_A), ["b", "c"])
        XCTAssertEqual(api.updateParams.first?.segmentsAdd, ["c"])
        XCTAssertEqual(api.updateParams.first?.segmentsRemove, ["a"])
    }

    func testGetUserProfileWhenDisabledAndSerialized() {
        host.cdpEnabled = false
        let disabled = manager.getUserProfile()
        XCTAssertNil(disabled.masterId)
        XCTAssertFalse(disabled.identityFresh)

        host.cdpEnabled = true
        host.masterId = UUID_A
        host.cached = CdpCachedIdentity(rfv: CdpRfv(rfv: 42, r: 3, f: 5, v: 7), cohorts: [101, 204])
        host.cachedSession = host.cdpSessionId
        let data = manager.getUserProfile()
        XCTAssertEqual(data.masterId, UUID_A)
        XCTAssertTrue(data.rfvSerialized.contains("\"rfv\":42"))
        XCTAssertEqual(data.cohortsSerialized, "[101,204]")
    }
}
