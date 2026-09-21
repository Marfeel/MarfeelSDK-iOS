//
//  CdpManagerConsentTests.swift
//  CompassSDKTests
//
//  Publisher consents: record, subject selection, canonical-master adoption, local
//  memory, catalog, check, hasConsent and replay.
//

import XCTest
@testable import CompassSDK

private let FOO_BAR_SHA256 = "0c7e6a405862e402eb76a70f8a26fc732d07c32931e9fae9ab1582911d2e8a3b"

final class CdpManagerConsentTests: XCTestCase {
    private var env: CdpTestEnv!
    private var manager: CdpManager { env.manager }
    private var api: MockCdpApi { env.api }
    private var host: MockCdpHost { env.host }

    private let recorded = CdpConsentRecordResponse(masterId: nil, consentId: "privacy", consentVersionId: "3", status: "accept", recorded: true, stored: true)

    override func setUp() {
        super.setUp()
        env = CdpTestEnv()
        host.cdpConsent = nil
    }

    override func tearDown() {
        env = nil
        super.tearDown()
    }

    private func decision(consentId: String = "privacy", versionId: String = "3", status: CdpConsentStatus = .accepted, metadata: [String: String]? = nil, email: String? = nil) -> CdpConsent {
        return CdpConsent(consentId: consentId, versionId: versionId, status: status, metadata: metadata, email: email)
    }

    private func record(_ decision: CdpConsent) -> CdpConsentRecordResponse? {
        var result: CdpConsentRecordResponse?
        waitFor("record") { done in self.manager.trackCdpConsent(decision) { result = $0; done() } }
        return result
    }

    private func check(_ query: CdpConsentQuery) -> CdpConsentCheck? {
        var result: CdpConsentCheck?
        waitFor("check") { done in self.manager.consentCheck(query) { result = $0; done() } }
        return result
    }

    private func has(_ query: CdpConsentQuery) -> Bool {
        var result = false
        waitFor("has") { done in self.manager.hasCdpConsent(query) { result = $0; done() } }
        return result
    }

    private func catalog(_ ref: CdpConsentRef) -> CdpConsentDefinition? {
        var result: CdpConsentDefinition?
        waitFor("catalog") { done in self.manager.getCdpConsent(ref) { result = $0; done() } }
        return result
    }

    private func replay() {
        waitFor("replay") { done in self.manager.replayConsentDecisions(completion: done) }
    }

    private func withMaster(_ masterId: String?) -> CdpConsentRecordResponse {
        return CdpConsentRecordResponse(masterId: masterId, consentId: "privacy", consentVersionId: "3", status: "accept", recorded: true, stored: true)
    }

    // MARK: - record

    func testRecordPostsTheFixedBodyWithTheResolvedMaster() {
        host.masterId = UUID_A
        api.recordResponses = [withMaster(UUID_A)]

        let result = record(decision(metadata: ["source": "footer"]))

        let params = api.recordParams.first!
        XCTAssertEqual(params.siteId, 456)
        XCTAssertEqual(params.masterId, UUID_A)
        XCTAssertEqual(params.consentId, "privacy")
        XCTAssertEqual(params.consentVersionId, "3")
        XCTAssertEqual(params.status, .accepted)
        XCTAssertEqual(params.metadata, ["source": "footer"])
        XCTAssertEqual(params.timezone, "Europe/Madrid")
        XCTAssertNil(params.idType)
        XCTAssertNil(params.idValue)
        XCTAssertEqual(result?.recorded, true)
    }

    func testRecordIsNotGatedOnCmpConsent() {
        host.cdpConsent = false
        api.recordResponses = [recorded]
        _ = record(decision())
        XCTAssertEqual(api.recordParams.count, 1)
    }

    func testRecordSendsANilMasterWhenNeverResolvedAndDefaultsMetadata() {
        env.timezone = nil
        api.recordResponses = [recorded]
        _ = record(decision())
        XCTAssertNil(api.recordParams.first?.masterId)
        XCTAssertEqual(api.recordParams.first?.metadata, [:])
        XCTAssertNil(api.recordParams.first?.timezone)
    }

    func testRecordSendsEveryCallAndAcceptsVersionZero() {
        api.recordResponses = [recorded, recorded]
        _ = record(decision(versionId: "0"))
        _ = record(decision(versionId: "0"))
        XCTAssertEqual(api.recordParams.count, 2)
        XCTAssertEqual(api.recordParams.first?.consentVersionId, "0")
    }

    func testRecordSkipsWhenTheConsentIdIsMissingOrCdpDisabled() {
        XCTAssertNil(record(decision(consentId: "")))
        host.cdpEnabled = false
        XCTAssertNil(record(decision()))
        XCTAssertEqual(api.recordParams.count, 0)
    }

    func testRecordReturnsNilOnATransportFailure() {
        api.recordResponses = [nil]
        XCTAssertNil(record(decision()))
    }

    // MARK: - subject

    func testSubjectHashedNormalisedEmailWhenThereIsNoMaster() {
        api.recordResponses = [recorded]
        _ = record(decision(email: "  Foo@Bar.com "))
        XCTAssertNil(api.recordParams.first?.masterId)
        XCTAssertEqual(api.recordParams.first?.idType, "email_sha256")
        XCTAssertEqual(api.recordParams.first?.idValue, FOO_BAR_SHA256)
    }

    func testSubjectMasterAndHashedEmailWhenBothExist() {
        host.masterId = UUID_A
        api.recordResponses = [withMaster(UUID_A)]
        _ = record(decision(email: "foo@bar.com"))
        XCTAssertEqual(api.recordParams.first?.masterId, UUID_A)
        XCTAssertEqual(api.recordParams.first?.idValue, FOO_BAR_SHA256)
    }

    func testSubjectNoIdKeysWithAMasterAndNoEmailAndEmptyEmailIsAbsent() {
        host.masterId = UUID_A
        api.recordResponses = [withMaster(UUID_A), withMaster(UUID_A)]
        _ = record(decision())
        _ = record(decision(email: ""))
        XCTAssertNil(api.recordParams[0].idType)
        XCTAssertNil(api.recordParams[1].idType)
    }

    // MARK: - canonical master

    func testCanonicalMasterAdoptsADifferentUuidKeepingTheCache() {
        host.masterId = UUID_A
        host.cached = CdpCachedIdentity(rfv: CdpRfv(rfv: 5, r: 1, f: 1, v: 1), cohorts: [3])
        host.cachedSession = host.cdpSessionId
        api.recordResponses = [withMaster(UUID_B)]

        _ = record(decision())

        XCTAssertEqual(host.masterId, UUID_B)
        XCTAssertEqual(env.masterIdChanges.count, 1)
        XCTAssertEqual(env.masterIdChanges.first?.1, UUID_B)
        XCTAssertEqual(host.cached?.rfv?.rfv, 5)
        XCTAssertEqual(host.cached?.cohorts, [3])
    }

    func testCanonicalMasterLeavesTheMasterAloneWhenEchoedAbsentOrNotAUuid() {
        host.masterId = UUID_A
        api.recordResponses = [withMaster(UUID_A), withMaster(nil), withMaster(""), withMaster("not-a-uuid")]
        for _ in 0..<4 { _ = record(decision()) }
        XCTAssertEqual(host.masterId, UUID_A)
        XCTAssertTrue(env.masterIdChanges.isEmpty)
    }

    func testCanonicalMasterNeverAdoptsWhenNoneWasSentTheDecisionIsRememberedInstead() {
        api.recordResponses = [withMaster(UUID_B)]
        _ = record(decision())
        XCTAssertNil(host.masterId)
        XCTAssertEqual(env.consentMemory.getRemembered(account: env.account)["privacy"]?.versionId, "3")
    }

    func testCanonicalMasterARecordThatStartedBeforeClearIdentityNeverAdopts() {
        host.masterId = UUID_A
        var release: ((CdpConsentRecordResponse?) -> Void)?
        let held = XCTestExpectation(description: "held")
        api.holdRecord = { completion in release = completion; held.fulfill() }
        let done = XCTestExpectation(description: "recorded")
        manager.trackCdpConsent(decision()) { _ in done.fulfill() }
        wait(for: [held], timeout: 2)

        manager.clearIdentity()
        release?(withMaster(UUID_B))
        wait(for: [done], timeout: 2)

        XCTAssertNil(host.masterId)
        XCTAssertTrue(env.masterIdChanges.isEmpty)
    }

    // MARK: - local memory

    func testMemoryRemembersARecordedDecisionWhenNoMasterWasSent() {
        env.now = 777
        api.recordResponses = [recorded]
        _ = record(decision(status: .rejected))
        let entry = env.consentMemory.getRemembered(account: env.account)["privacy"]
        XCTAssertEqual(entry?.versionId, "3")
        XCTAssertEqual(entry?.status, .rejected)
        XCTAssertEqual(entry?.ts, 777)
    }

    func testMemoryDoesNotRememberWithAMasterOrWhenNotRecorded() {
        host.masterId = UUID_A
        api.recordResponses = [withMaster(UUID_A)]
        _ = record(decision())
        XCTAssertTrue(env.consentMemory.getRemembered(account: env.account).isEmpty)

        host.masterId = nil
        api.recordResponses = [CdpConsentRecordResponse(masterId: nil, consentId: "privacy", consentVersionId: "3", status: "accept", recorded: false, stored: false)]
        _ = record(decision())
        XCTAssertTrue(env.consentMemory.getRemembered(account: env.account).isEmpty)
    }

    // MARK: - catalog

    private func catalogItem(showPolicy: String? = "if-not-accepted", acceptMethod: String = "check-box", version: Bool = true) -> CdpConsentCatalogItem {
        return CdpConsentCatalogItem(
            consentId: "privacy", name: "Privacy policy", purpose: "legal", mandatory: true,
            acceptMethod: acceptMethod, showPolicy: showPolicy,
            version: version ? CdpConsentCatalogVersionItem(versionId: "3", label: "v3", date: "2026-01-01", displayPrompt: "Please accept", errorMessage: "You must accept", metadata: ["k": "v"]) : nil
        )
    }

    func testCatalogQueriesBySiteAndConsentWithTheVersionAsGiven() {
        api.catalogResponses = [[catalogItem()], [catalogItem()]]
        _ = catalog(CdpConsentRef(consentId: "privacy", versionId: "3"))
        _ = catalog(CdpConsentRef(consentId: "privacy"))
        XCTAssertEqual(api.catalogCalls[0].siteId, 456)
        XCTAssertEqual(api.catalogCalls[0].versionId, "3")
        XCTAssertNil(api.catalogCalls[1].versionId)
    }

    func testCatalogMapsTheItemToTheDefinition() {
        api.catalogResponses = [[catalogItem()]]
        let definition = catalog(CdpConsentRef(consentId: "privacy", versionId: "3"))!
        XCTAssertEqual(definition.consentId, "privacy")
        XCTAssertEqual(definition.name, "Privacy policy")
        XCTAssertEqual(definition.purpose, "legal")
        XCTAssertTrue(definition.mandatory)
        XCTAssertEqual(definition.acceptMethod, "check-box")
        XCTAssertEqual(definition.showPolicy, .ifNotAccepted)
        XCTAssertEqual(definition.version?.versionId, "3")
        XCTAssertEqual(definition.version?.label, "v3")
        XCTAssertEqual(definition.version?.date, "2026-01-01")
        XCTAssertEqual(definition.version?.displayPrompt, "Please accept")
        XCTAssertEqual(definition.version?.errorMessage, "You must accept")
        XCTAssertEqual(definition.version?.metadata, ["k": "v"])
    }

    func testCatalogAcceptMethodPassesThroughVerbatim() {
        for method in ["check-box", "pre-checked", "form-submit", "something-new"] {
            api.catalogResponses = [[catalogItem(acceptMethod: method)]]
            XCTAssertEqual(catalog(CdpConsentRef(consentId: "privacy"))?.acceptMethod, method)
        }
    }

    func testCatalogShowPolicyFoldsEverythingButTheExactValueToAlways() {
        let cases: [(String?, CdpConsentShowPolicy)] = [("always", .always), ("if-not-accepted", .ifNotAccepted), (nil, .always), ("never", .always), ("If-Not-Accepted", .always)]
        for (wire, expected) in cases {
            api.catalogResponses = [[catalogItem(showPolicy: wire)]]
            XCTAssertEqual(catalog(CdpConsentRef(consentId: "privacy"))?.showPolicy, expected, "show_policy=\(wire ?? "nil")")
        }
    }

    func testCatalogVersionIsNilWhenAbsentAndNilResults() {
        api.catalogResponses = [[catalogItem(version: false)]]
        XCTAssertNil(catalog(CdpConsentRef(consentId: "privacy"))?.version)

        api.catalogResponses = [[]]
        XCTAssertNil(catalog(CdpConsentRef(consentId: "privacy", versionId: "99")))
        api.catalogResponses = [nil]
        XCTAssertNil(catalog(CdpConsentRef(consentId: "privacy")))
        XCTAssertNil(catalog(CdpConsentRef(consentId: "")))
        host.cdpEnabled = false
        XCTAssertNil(catalog(CdpConsentRef(consentId: "privacy")))
        XCTAssertEqual(api.catalogCalls.count, 3)
    }

    func testCatalogIsNotGatedOnCmpConsent() {
        host.cdpConsent = false
        api.catalogResponses = [[catalogItem()]]
        XCTAssertEqual(catalog(CdpConsentRef(consentId: "privacy"))?.consentId, "privacy")
    }

    // MARK: - check

    private func checkResponse(granted: Bool = true, answered: Bool = true, status: String? = "accepted", versionId: String? = "3", answeredVersionId: String? = "3") -> CdpConsentCheckResponse {
        return CdpConsentCheckResponse(masterId: UUID_A, consentId: "privacy", consentVersionId: versionId, granted: granted, answered: answered, status: status, answeredVersionId: answeredVersionId)
    }

    func testCheckSendsOnlyTheMasterWhenNoEmailIsGiven() {
        host.masterId = UUID_A
        api.checkResponses = [checkResponse()]
        _ = check(CdpConsentQuery(consentId: "privacy", versionId: "3"))
        let params = api.checkParams.first!
        XCTAssertEqual(params.masterId, UUID_A)
        XCTAssertEqual(params.consentVersionId, "3")
        XCTAssertNil(params.idType)
    }

    func testCheckSendsTheHashedEmailWithoutAMasterAndAlongsideOne() {
        api.checkResponses = [checkResponse(), checkResponse()]
        _ = check(CdpConsentQuery(consentId: "privacy", email: " FOO@bar.com"))
        XCTAssertNil(api.checkParams[0].masterId)
        XCTAssertNil(api.checkParams[0].consentVersionId)
        XCTAssertEqual(api.checkParams[0].idType, "email_sha256")
        XCTAssertEqual(api.checkParams[0].idValue, FOO_BAR_SHA256)

        host.masterId = UUID_A
        _ = check(CdpConsentQuery(consentId: "privacy", email: "foo@bar.com"))
        XCTAssertEqual(api.checkParams[1].masterId, UUID_A)
        XCTAssertEqual(api.checkParams[1].idValue, FOO_BAR_SHA256)
    }

    func testCheckWithNeitherAnswersFromMemoryAndNeverCallsTheNetwork() {
        env.consentMemory.remember(account: env.account, consentId: "privacy", decision: CdpRememberedConsentDecision(versionId: "3", status: .accepted, ts: 1))
        let status = check(CdpConsentQuery(consentId: "privacy", versionId: "3"))!
        XCTAssertTrue(status.granted)
        XCTAssertNil(status.masterId)
        XCTAssertEqual(api.checkParams.count, 0)
        XCTAssertEqual(api.catalogCalls.count, 0)
    }

    func testCheckMapsTheServerAnswer() {
        host.masterId = UUID_A
        api.checkResponses = [checkResponse()]
        let status = check(CdpConsentQuery(consentId: "privacy", versionId: "3"))!
        XCTAssertEqual(status.masterId, UUID_A)
        XCTAssertEqual(status.versionId, "3")
        XCTAssertTrue(status.granted)
        XCTAssertTrue(status.answered)
        XCTAssertEqual(status.status, .accepted)
        XCTAssertEqual(status.answeredVersionId, "3")
    }

    func testCheckUnansweredAndRejectionOnOlderVersion() {
        host.masterId = UUID_A
        api.checkResponses = [checkResponse(granted: false, answered: false, status: nil, answeredVersionId: nil), checkResponse(granted: false, answered: true, status: "reject", answeredVersionId: "2")]
        let unanswered = check(CdpConsentQuery(consentId: "privacy", versionId: "3"))!
        XCTAssertFalse(unanswered.answered)
        XCTAssertNil(unanswered.status)
        XCTAssertNil(unanswered.answeredVersionId)

        let rejected = check(CdpConsentQuery(consentId: "privacy", versionId: "3"))!
        XCTAssertFalse(rejected.granted)
        XCTAssertTrue(rejected.answered)
        XCTAssertEqual(rejected.status, .rejected)
        XCTAssertEqual(rejected.answeredVersionId, "2")
    }

    func testCheckNilOnTransportErrorMissingIdOrDisabledAndNotCmpGated() {
        host.masterId = UUID_A
        host.cdpConsent = false
        api.checkResponses = [nil]
        XCTAssertNil(check(CdpConsentQuery(consentId: "privacy")))
        XCTAssertEqual(api.checkParams.count, 1)
        XCTAssertNil(check(CdpConsentQuery(consentId: "")))
        host.cdpEnabled = false
        XCTAssertNil(check(CdpConsentQuery(consentId: "privacy")))
        XCTAssertEqual(api.checkParams.count, 1)
    }

    // MARK: - memory answers

    func testMemoryAnswerUnansweredEchoesTheRequestedVersionOrEmpty() {
        let withVersion = check(CdpConsentQuery(consentId: "privacy", versionId: "3"))!
        XCTAssertFalse(withVersion.answered)
        XCTAssertEqual(withVersion.versionId, "3")
        XCTAssertEqual(check(CdpConsentQuery(consentId: "privacy"))!.versionId, "")
    }

    func testMemoryAnswerGrantedOnlyOnAnExactVersionMatch() {
        env.consentMemory.remember(account: env.account, consentId: "privacy", decision: CdpRememberedConsentDecision(versionId: "3", status: .accepted, ts: 1))
        let same = check(CdpConsentQuery(consentId: "privacy", versionId: "3"))!
        XCTAssertTrue(same.granted)
        XCTAssertEqual(same.status, .accepted)
        XCTAssertEqual(same.answeredVersionId, "3")

        let other = check(CdpConsentQuery(consentId: "privacy", versionId: "4"))!
        XCTAssertFalse(other.granted)
        XCTAssertTrue(other.answered)
        XCTAssertEqual(other.versionId, "4")
        XCTAssertEqual(other.answeredVersionId, "3")
    }

    func testMemoryAnswerRejectionAndAnyAcceptWithoutVersion() {
        env.consentMemory.remember(account: env.account, consentId: "privacy", decision: CdpRememberedConsentDecision(versionId: "2", status: .rejected, ts: 1))
        let rejected = check(CdpConsentQuery(consentId: "privacy"))!
        XCTAssertTrue(rejected.answered)
        XCTAssertFalse(rejected.granted)

        env.consentMemory.remember(account: env.account, consentId: "privacy", decision: CdpRememberedConsentDecision(versionId: "2", status: .accepted, ts: 1))
        let any = check(CdpConsentQuery(consentId: "privacy"))!
        XCTAssertTrue(any.granted)
        XCTAssertEqual(any.versionId, "2")
        XCTAssertEqual(any.answeredVersionId, "2")
    }

    // MARK: - hasCdpConsent

    func testHasConsentTrueOnlyWhenGranted() {
        host.masterId = UUID_A
        api.checkResponses = [checkResponse(granted: true), checkResponse(granted: false), nil]
        XCTAssertTrue(has(CdpConsentQuery(consentId: "privacy", versionId: "3")))
        XCTAssertFalse(has(CdpConsentQuery(consentId: "privacy", versionId: "3")))
        XCTAssertFalse(has(CdpConsentQuery(consentId: "privacy", versionId: "3")))
        host.cdpEnabled = false
        XCTAssertFalse(has(CdpConsentQuery(consentId: "privacy", versionId: "3")))
        XCTAssertEqual(api.checkParams.count, 3)
    }

    func testHasConsentAnswersFromMemoryForAnAnonymousVisitor() {
        env.consentMemory.remember(account: env.account, consentId: "privacy", decision: CdpRememberedConsentDecision(versionId: "3", status: .accepted, ts: 1))
        XCTAssertTrue(has(CdpConsentQuery(consentId: "privacy", versionId: "3")))
        XCTAssertFalse(has(CdpConsentQuery(consentId: "newsletter")))
        XCTAssertEqual(api.checkParams.count, 0)
    }

    // MARK: - replay

    func testReplayReRecordsEachRememberedDecisionOnceUnderTheMasterAndNothingElse() {
        host.masterId = UUID_A
        env.consentMemory.remember(account: env.account, consentId: "privacy", decision: CdpRememberedConsentDecision(versionId: "3", status: .accepted, ts: 1))
        env.consentMemory.remember(account: env.account, consentId: "newsletter", decision: CdpRememberedConsentDecision(versionId: "1", status: .rejected, ts: 2))
        api.recordResponses = [recorded, recorded]

        replay()

        XCTAssertEqual(api.recordParams.count, 2)
        let privacy = api.recordParams.first { $0.consentId == "privacy" }!
        XCTAssertEqual(privacy.masterId, UUID_A)
        XCTAssertEqual(privacy.consentVersionId, "3")
        XCTAssertEqual(privacy.status, .accepted)
        XCTAssertNil(privacy.metadata)
        XCTAssertNil(privacy.timezone)
        XCTAssertNil(privacy.idType)
        XCTAssertEqual(api.recordParams.first { $0.consentId == "newsletter" }?.status, .rejected)
        XCTAssertTrue(env.consentMemory.getRemembered(account: env.account).isEmpty)
    }

    func testReplayForgetsOnlyTheDecisionsTheServerRecorded() {
        host.masterId = UUID_A
        env.consentMemory.remember(account: env.account, consentId: "privacy", decision: CdpRememberedConsentDecision(versionId: "3", status: .accepted, ts: 1))
        api.recordResponses = [CdpConsentRecordResponse(masterId: nil, consentId: "privacy", consentVersionId: "3", status: "accept", recorded: false, stored: false)]

        replay()

        XCTAssertEqual(Array(env.consentMemory.getRemembered(account: env.account).keys), ["privacy"])
    }

    func testReplayIsANoOpWithNothingRememberedWithoutAMasterOrWhenDisabled() {
        host.masterId = UUID_A
        replay()
        env.consentMemory.remember(account: env.account, consentId: "privacy", decision: CdpRememberedConsentDecision(versionId: "3", status: .accepted, ts: 1))
        host.masterId = nil
        replay()
        host.masterId = UUID_A
        host.cdpEnabled = false
        replay()
        XCTAssertEqual(api.recordParams.count, 0)
        XCTAssertEqual(Array(env.consentMemory.getRemembered(account: env.account).keys), ["privacy"])
    }

    func testReplayDoesNotDoubleFireWhileInFlightAndReArmsAfter() {
        host.masterId = UUID_A
        env.consentMemory.remember(account: env.account, consentId: "privacy", decision: CdpRememberedConsentDecision(versionId: "3", status: .accepted, ts: 1))
        var release: ((CdpConsentRecordResponse?) -> Void)?
        let held = XCTestExpectation(description: "held")
        api.holdRecord = { completion in release = completion; held.fulfill() }
        let first = XCTestExpectation(description: "first")
        let second = XCTestExpectation(description: "second")
        manager.replayConsentDecisions { first.fulfill() }
        manager.replayConsentDecisions { second.fulfill() }
        wait(for: [held], timeout: 2)
        release?(CdpConsentRecordResponse(masterId: nil, consentId: "privacy", consentVersionId: "3", status: "accept", recorded: false, stored: false))
        wait(for: [first, second], timeout: 2)
        XCTAssertEqual(api.recordParams.count, 1)

        api.holdRecord = nil
        api.recordResponses = [recorded]
        replay()
        XCTAssertEqual(api.recordParams.count, 2)
    }
}
