//
//  CdpApiClientTests.swift
//  CompassSDKTests
//
//  Wire format of every CDP endpoint through a stubbed URLProtocol: paths (trailing
//  slashes), methods, bodies (absent vs explicit null), response parsing and the
//  failure values.
//

import XCTest
@testable import CompassSDK

final class StubURLProtocol: URLProtocol {
    struct Recorded {
        let request: URLRequest
        let body: [String: Any]?
    }

    static var responder: ((URLRequest) -> (Int, Data?))?
    static var recorded: [Recorded] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let bodyData = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open()
            defer { stream.close() }
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 4096)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }
        let body = bodyData.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        StubURLProtocol.recorded.append(Recorded(request: request, body: body))

        let (status, data) = StubURLProtocol.responder?(request) ?? (200, "{}".data(using: .utf8))
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = data { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class CdpApiClientTests: XCTestCase {
    private var client: CdpApiClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.recorded = []
        StubURLProtocol.responder = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        client = CdpApiClient(session: URLSession(configuration: configuration), baseUrl: URL(string: "https://cdp.test/"))
    }

    private func respond(_ status: Int = 200, _ json: String = "{}") {
        StubURLProtocol.responder = { _ in (status, json.data(using: .utf8)) }
    }

    private var last: StubURLProtocol.Recorded { StubURLProtocol.recorded.last! }

    // MARK: - identity

    func testResolvePostsToTheResolvePathWithTrailingSlashAndNumericSiteId() {
        respond(200, "{\"master_id\":\"abc\"}")
        waitFor { done in self.client.resolve(CdpResolveParams(siteId: 123, cookieId: "u1", masterId: nil)) { _ in done() } }
        XCTAssertEqual(last.request.httpMethod, "POST")
        XCTAssertTrue(last.request.url?.absoluteString.hasPrefix("https://cdp.test/cdp/identity/resolve/") ?? false, "path must keep its trailing slash: \(last.request.url?.absoluteString ?? "")")
        XCTAssertEqual(last.body?["site_id"] as? Int, 123)
        XCTAssertEqual(last.body?["cookie_id"] as? String, "u1")
        XCTAssertNil(last.body?["master_id"])
    }

    func testIdentityResponsesParseSegmentsAndCoerceProperties() {
        respond(200, "{\"master_id\":\"m\",\"rfv\":{\"rfv\":42,\"r\":3,\"f\":5,\"v\":7},\"cohorts\":[101,204],\"segments\":[\"a\",\"b\"],\"properties\":{\"plan\":\"premium\",\"age\":42,\"vip\":true,\"nested\":{\"x\":1},\"gone\":null}}")
        var result: CdpIdentityResponse?
        waitFor { done in self.client.resolve(CdpResolveParams(siteId: 1, cookieId: "u", masterId: nil)) { result = $0; done() } }
        XCTAssertEqual(result?.masterId, "m")
        XCTAssertEqual(result?.rfv?.rfv, 42)
        XCTAssertEqual(result?.cohorts, [101, 204])
        XCTAssertEqual(result?.segments, ["a", "b"])
        XCTAssertEqual(result?.properties?["plan"], "premium")
        XCTAssertEqual(result?.properties?["age"], "42")
        XCTAssertEqual(result?.properties?["vip"], "true")
        XCTAssertEqual(result?.properties?["nested"], "{\"x\":1}")
        XCTAssertNil(result?.properties?["gone"])
    }

    func testIdentityResponsesLeaveSegmentsAndPropertiesNilWhenAbsentAndFailOpen() {
        respond(200, "{\"master_id\":\"m\"}")
        var result: CdpIdentityResponse?
        waitFor { done in self.client.resolve(CdpResolveParams(siteId: 1, cookieId: "u", masterId: nil)) { result = $0; done() } }
        XCTAssertNil(result?.segments)
        XCTAssertNil(result?.properties)

        respond(500)
        waitFor { done in self.client.resolve(CdpResolveParams(siteId: 1, cookieId: "u", masterId: nil)) { result = $0; done() } }
        XCTAssertEqual(result, UNKNOWN_CDP_IDENTITY)

        respond(200, "not json")
        waitFor { done in self.client.link(CdpLinkParams(siteId: 1, idType: "email", idValue: "x", isDeterministic: true, masterId: nil)) { result = $0; done() } }
        XCTAssertNil(result?.masterId)
    }

    // MARK: - delete / reset

    func testDeletePostsTheSnakeCaseBodyAndParsesTheCount() {
        respond(200, "{\"master_id\":\"m\",\"segments\":[\"s\"],\"deleted\":2}")
        var result: CdpDeleteResponse?
        waitFor { done in self.client.delete(CdpDeleteParams(siteId: 1, masterId: "m", idType: "email", idValue: "x@y.z")) { result = $0; done() } }
        XCTAssertTrue(last.request.url?.absoluteString.hasPrefix("https://cdp.test/cdp/identity/delete/") ?? false, "path must keep its trailing slash: \(last.request.url?.absoluteString ?? "")")
        XCTAssertEqual(last.body?["site_id"] as? Int, 1)
        XCTAssertEqual(last.body?["master_id"] as? String, "m")
        XCTAssertEqual(last.body?["id_type"] as? String, "email")
        XCTAssertEqual(last.body?["id_value"] as? String, "x@y.z")
        XCTAssertEqual(result?.deleted, 2)
        XCTAssertEqual(result?.identity.segments, ["s"])
    }

    func testDeleteOmitsIdValueEntirelyWhenNilAndReturnsNilOnFailure() {
        respond(200, "{\"master_id\":\"m\",\"deleted\":0}")
        waitFor { done in self.client.delete(CdpDeleteParams(siteId: 1, masterId: "m", idType: "crm_id")) { _ in done() } }
        XCTAssertNil(last.body?["id_value"])
        XCTAssertFalse(last.body?.keys.contains("id_value") ?? true)

        respond(500)
        var result: CdpDeleteResponse? = CdpDeleteResponse(identity: UNKNOWN_CDP_IDENTITY, deleted: 0)
        waitFor { done in self.client.delete(CdpDeleteParams(siteId: 1, masterId: "m", idType: "email", idValue: "v")) { result = $0; done() } }
        XCTAssertNil(result)
    }

    func testResetPostsOnlyTheSiteIdAndParsesTheClearedList() {
        respond(200, "{\"reset\":true,\"site_id\":1,\"cleared\":[\"1_u\",\"1_s\"]}")
        var result: CdpResetResponse?
        waitFor { done in self.client.reset(siteId: 1) { result = $0; done() } }
        XCTAssertTrue(last.request.url?.absoluteString.hasPrefix("https://cdp.test/cdp/identity/reset/") ?? false, "path must keep its trailing slash: \(last.request.url?.absoluteString ?? "")")
        XCTAssertEqual(last.body?.count, 1)
        XCTAssertEqual(last.body?["site_id"] as? Int, 1)
        XCTAssertEqual(result?.reset, true)
        XCTAssertEqual(result?.siteId, 1)
        XCTAssertEqual(result?.cleared, ["1_u", "1_s"])

        respond(503)
        waitFor { done in self.client.reset(siteId: 1) { result = $0; done() } }
        XCTAssertNil(result)
    }

    // MARK: - consents

    func testRecordConsentSendsAnExplicitNullMasterAndOmitsTheOptionalKeys() {
        respond(200, "{\"consent_id\":\"p\",\"consent_version_id\":\"1\",\"status\":\"accept\",\"recorded\":true,\"stored\":true}")
        var result: CdpConsentRecordResponse?
        waitFor { done in self.client.recordConsent(CdpConsentRecordParams(siteId: 1, masterId: nil, consentId: "p", consentVersionId: "1", status: .accepted)) { result = $0; done() } }
        XCTAssertTrue(last.request.url?.absoluteString.hasPrefix("https://cdp.test/cdp/consents/record/") ?? false, "path must keep its trailing slash: \(last.request.url?.absoluteString ?? "")")
        XCTAssertTrue(last.body?["master_id"] is NSNull)
        XCTAssertEqual(last.body?["status"] as? String, "accepted")
        XCTAssertEqual(last.body?["consent_version_id"] as? String, "1")
        XCTAssertNil(last.body?["metadata"])
        XCTAssertNil(last.body?["timezone"])
        XCTAssertNil(last.body?["id_type"])
        XCTAssertEqual(result?.recorded, true)
        XCTAssertEqual(result?.status, "accept")
        XCTAssertNil(result?.masterId)
    }

    func testRecordConsentSendsMetadataTimezoneAndTheEmailSubject() {
        respond(200, "{\"master_id\":\"m\",\"recorded\":true,\"stored\":true}")
        var params = CdpConsentRecordParams(siteId: 1, masterId: "m", consentId: "p", consentVersionId: "1", status: .rejected)
        params.metadata = ["source": "footer"]
        params.timezone = "Europe/Madrid"
        params.idType = "email_sha256"
        params.idValue = "abc"
        waitFor { done in self.client.recordConsent(params) { _ in done() } }
        XCTAssertEqual(last.body?["master_id"] as? String, "m")
        XCTAssertEqual(last.body?["metadata"] as? [String: String], ["source": "footer"])
        XCTAssertEqual(last.body?["timezone"] as? String, "Europe/Madrid")
        XCTAssertEqual(last.body?["id_type"] as? String, "email_sha256")
        XCTAssertEqual(last.body?["id_value"] as? String, "abc")
        XCTAssertEqual(last.body?["status"] as? String, "rejected")
        XCTAssertNil(last.body?["ip"])
        XCTAssertNil(last.body?["user_agent"])
    }

    func testRecordConsentReturnsNilOnFailure() {
        respond(500)
        var result: CdpConsentRecordResponse? = CdpConsentRecordResponse(masterId: nil, consentId: nil, consentVersionId: nil, status: nil, recorded: true, stored: true)
        waitFor { done in self.client.recordConsent(CdpConsentRecordParams(siteId: 1, masterId: nil, consentId: "p", consentVersionId: "1", status: .accepted)) { result = $0; done() } }
        XCTAssertNil(result)
    }

    func testFetchConsentCatalogIsAGetWithTheVersionAsAQueryParamOmittedWhenAbsent() {
        respond(200, "{\"site_id\":1,\"consents\":[]}")
        waitFor { done in self.client.fetchConsentCatalog(siteId: 1, consentId: "privacy policy", versionId: "3") { _ in done() } }
        XCTAssertEqual(last.request.httpMethod, "GET")
        XCTAssertTrue(last.request.url?.absoluteString.hasPrefix("https://cdp.test/cdp/consents/catalog/") ?? false, "path must keep its trailing slash: \(last.request.url?.absoluteString ?? "")")
        let query = last.request.url?.query ?? ""
        XCTAssertTrue(query.contains("site_id=1"))
        XCTAssertTrue(query.contains("consent_id=privacy%20policy"))
        XCTAssertTrue(query.contains("consent_version_id=3"))

        waitFor { done in self.client.fetchConsentCatalog(siteId: 1, consentId: "privacy", versionId: nil) { _ in done() } }
        XCTAssertFalse(last.request.url?.query?.contains("consent_version_id") ?? true)
    }

    func testFetchConsentCatalogParsesTheWireItemAndFailureValues() {
        respond(200, "{\"site_id\":1,\"consents\":[{\"consent_id\":\"privacy\",\"name\":\"Privacy\",\"purpose\":null,\"mandatory\":true,\"accept_method\":\"form-submit\",\"show_policy\":\"if-not-accepted\",\"version\":{\"consent_version_id\":7,\"label\":\"v7\",\"date\":\"2026-01-01\",\"display_prompt\":null,\"error_message\":\"nope\",\"metadata\":{\"a\":\"b\"}}}]}")
        var items: [CdpConsentCatalogItem]?
        waitFor { done in self.client.fetchConsentCatalog(siteId: 1, consentId: "privacy", versionId: nil) { items = $0; done() } }
        let item = items?.first
        XCTAssertEqual(item?.consentId, "privacy")
        XCTAssertNil(item?.purpose)
        XCTAssertEqual(item?.mandatory, true)
        XCTAssertEqual(item?.acceptMethod, "form-submit")
        XCTAssertEqual(item?.showPolicy, "if-not-accepted")
        XCTAssertEqual(item?.version?.versionId, "7")
        XCTAssertNil(item?.version?.displayPrompt)
        XCTAssertEqual(item?.version?.errorMessage, "nope")
        XCTAssertEqual(item?.version?.metadata, ["a": "b"])

        respond(200, "{\"site_id\":1,\"consents\":[]}")
        waitFor { done in self.client.fetchConsentCatalog(siteId: 1, consentId: "privacy", versionId: "99") { items = $0; done() } }
        XCTAssertEqual(items?.count, 0)
        respond(500)
        waitFor { done in self.client.fetchConsentCatalog(siteId: 1, consentId: "privacy", versionId: nil) { items = $0; done() } }
        XCTAssertNil(items)
    }

    func testFetchConsentStatusIsAPostCarryingOnlyThePresentSubjectKeys() {
        respond(200, "{\"master_id\":\"m\",\"consent_id\":\"p\",\"consent_version_id\":\"1\",\"granted\":true,\"answered\":true,\"status\":\"accepted\",\"answered_version_id\":\"1\"}")
        var result: CdpConsentCheckResponse?
        var params = CdpConsentCheckParams(siteId: 1, consentId: "p")
        params.consentVersionId = "1"
        params.masterId = "m"
        waitFor { done in self.client.fetchConsentStatus(params) { result = $0; done() } }
        XCTAssertEqual(last.request.httpMethod, "POST")
        XCTAssertTrue(last.request.url?.absoluteString.hasPrefix("https://cdp.test/cdp/consents/check/") ?? false, "path must keep its trailing slash: \(last.request.url?.absoluteString ?? "")")
        XCTAssertEqual(last.body?["master_id"] as? String, "m")
        XCTAssertNil(last.body?["id_type"])
        XCTAssertEqual(result?.granted, true)
        XCTAssertEqual(result?.status, "accepted")
        XCTAssertEqual(result?.answeredVersionId, "1")

        respond(500)
        waitFor { done in self.client.fetchConsentStatus(params) { result = $0; done() } }
        XCTAssertNil(result)
    }
}
