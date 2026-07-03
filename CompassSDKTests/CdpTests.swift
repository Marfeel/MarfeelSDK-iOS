//
//  CdpTests.swift
//  CompassSDKTests
//
//  Unit tests for the CDP subsystem's pure logic (no network):
//  mirror-store TTL/cleanup, meter parsing, segment local-first + carry-over,
//  fail-open response decoding, and beacon serialization.
//

import XCTest
@testable import CompassSDK

final class CdpTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "CdpTestsSuite"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Mirror store

    func testMirrorStoreReadWriteRoundTrip() {
        let store = CdpSegmentsStore(defaults: defaults)
        store.write(account: "123", masterId: "mid", value: ["a", "b"])
        XCTAssertEqual(store.read(account: "123", masterId: "mid"), ["a", "b"])
    }

    func testMirrorStoreNoOpOnFalsyKeys() {
        let store = CdpSegmentsStore(defaults: defaults)
        store.write(account: nil, masterId: "mid", value: ["a"])
        store.write(account: "123", masterId: nil, value: ["a"])
        XCTAssertEqual(store.read(account: nil, masterId: "mid"), [])
        XCTAssertEqual(store.read(account: "123", masterId: nil), [])
    }

    func testMirrorStoreTTLExpiry() {
        var now: Int64 = 1_000_000
        let store = CdpSegmentsStore(defaults: defaults, clock: { now })
        store.write(account: "123", masterId: "mid", value: ["a"])
        XCTAssertEqual(store.read(account: "123", masterId: "mid"), ["a"])

        now += CDP_MIRROR_TTL_MS // exactly at TTL → stale
        XCTAssertEqual(store.read(account: "123", masterId: "mid"), [])
    }

    func testCleanupNeverPurgesActiveMid() {
        var now: Int64 = 1_000_000
        let store = CdpSegmentsStore(defaults: defaults, clock: { now })
        store.write(account: "123", masterId: "stale", value: ["drop"])

        now += CDP_MIRROR_TTL_MS + 1 // "stale" bucket is now past TTL
        // Write the active bucket fresh at the new "now".
        store.write(account: "123", masterId: "active", value: ["keep"])

        store.cleanupExpired(account: "123", activeMidOverride: "active")

        // Active (fresh) bucket survives; stale bucket data is purged.
        XCTAssertEqual(store.read(account: "123", masterId: "active"), ["keep"])
        XCTAssertEqual(store.read(account: "123", masterId: "stale"), [])
    }

    // MARK: - Meter parsing

    func testMeterParsingPreservesAbsentThreshold() {
        let raw: [String: Any] = ["name": "paywall", "count": 3]
        let meter = MeterState.from(json: raw)
        XCTAssertEqual(meter.name, "paywall")
        XCTAssertEqual(meter.count, 3)
        XCTAssertNil(meter.threshold)
        XCTAssertNil(meter.reached)
        XCTAssertNil(meter.remaining)
    }

    func testMeterParsingWithThreshold() {
        let raw: [String: Any] = [
            "name": "paywall", "count": 3,
            "threshold": 5, "reached": false, "remaining": 2,
            "window": ["duration": "calendar", "period": "P1M", "tz": "Europe/Madrid"]
        ]
        let meter = MeterState.from(json: raw)
        XCTAssertEqual(meter.threshold, 5)
        XCTAssertEqual(meter.reached, false)
        XCTAssertEqual(meter.remaining, 2)
        XCTAssertEqual(meter.window.period, "P1M")
        XCTAssertEqual(meter.window.tz, "Europe/Madrid")
    }

    func testMeterStorePersistenceRoundTrip() {
        let store = CdpMetersStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let meter = MeterState(name: "m", count: 4, threshold: 10, reached: false, remaining: 6, startedAt: date, window: MeterWindow(duration: "rolling", period: "P7D", tz: "UTC"))
        store.write(account: "1", masterId: "mid", value: [meter])

        let read = store.read(account: "1", masterId: "mid")
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read.first?.name, "m")
        XCTAssertEqual(read.first?.threshold, 10)
        XCTAssertEqual(read.first?.window.period, "P7D")
        XCTAssertNotNil(read.first?.startedAt)
    }

    // MARK: - Fail-open decoding

    func testIdentityResponseDecode() {
        let json = "{\"master_id\":\"550e8400-e29b-41d4-a716-446655440000\",\"rfv\":{\"rfv\":42,\"r\":3,\"f\":5,\"v\":7},\"cohorts\":[101,204]}"
        let response = CdpIdentityResponse.decode(from: json.data(using: .utf8)!)
        XCTAssertEqual(response?.masterId, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(response?.rfv?.rfv, 42)
        XCTAssertEqual(response?.cohorts, [101, 204])
    }

    func testIdentityResponseDecodeMissingCohorts() {
        let json = "{\"master_id\":null,\"rfv\":null}"
        let response = CdpIdentityResponse.decode(from: json.data(using: .utf8)!)
        XCTAssertNil(response?.masterId)
        XCTAssertNil(response?.rfv)
        XCTAssertEqual(response?.cohorts, [])
    }

    // MARK: - CdpManager segment logic (local-first, carry-over)

    private final class MockCdpHost: CdpHost {
        var cdpEnabled: Bool
        var cdpAccountId: Int?
        var cdpConsent: Bool?
        var masterId: String?
        var cdpUserId = "cookie"
        var cdpSessionId = "session"
        var cdpUserVars: [String: String] = [:]
        var legacySegments: [String] = []

        init(enabled: Bool, consent: Bool?, account: Int?, masterId: String?) {
            self.cdpEnabled = enabled
            self.cdpConsent = consent
            self.cdpAccountId = account
            self.masterId = masterId
        }

        func cdpReadMasterId() -> String? { masterId }
        func cdpWriteMasterId(_ id: String) -> String? { let old = masterId; masterId = id; return old }
        func cdpReadCachedIdentity(sessionId: String) -> CdpCachedIdentity? { nil }
        func cdpWriteCachedIdentity(rfv: CdpRfv?, cohorts: [Int], sessionId: String) {}
        var cdpLegacySegments: [String] { legacySegments }
        func cdpWriteLegacySegments(_ segments: [String]) { legacySegments = segments }
    }

    private func makeManager(enabled: Bool = true, consent: Bool? = true, account: Int? = 123, masterId: String?, segmentsStore: CdpSegmentsStore) -> CdpManager {
        let host = MockCdpHost(enabled: enabled, consent: consent, account: account, masterId: masterId)
        return CdpManager(api: CdpApiClient(), host: host, segmentsStore: segmentsStore)
    }

    func testSegmentsWrittenLocallyToLocalBucketWithoutMasterId() {
        let store = CdpSegmentsStore(defaults: defaults)
        let manager = makeManager(masterId: nil, segmentsStore: store)
        manager.addSegment("sports_fan")

        let expectation = XCTestExpectation(description: "segment written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Pre-identity segments land in the "local" bucket.
            XCTAssertEqual(store.read(account: "123", masterId: LOCAL_MID_SENTINEL), ["sports_fan"])
            XCTAssertEqual(manager.getCdpSegments(), ["sports_fan"])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testMergeLegacySegmentsUnionsIntoCdpStoreAndWritesBack() {
        let store = CdpSegmentsStore(defaults: defaults)
        let host = MockCdpHost(enabled: true, consent: true, account: 123, masterId: "mid-1")
        host.legacySegments = ["sports_fan", "premium"]
        // A segment already in the CDP store (e.g. set via addCdpSegment before resolve).
        store.write(account: "123", masterId: "mid-1", value: ["premium", "newsletter"])
        let manager = CdpManager(api: CdpApiClient(), host: host, segmentsStore: store)

        manager.mergeLegacySegments()

        let expectation = XCTestExpectation(description: "merged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Union of CDP store + legacy, deduped.
            XCTAssertEqual(Set(store.read(account: "123", masterId: "mid-1")), ["premium", "newsletter", "sports_fan"])
            // Union written back to the legacy store too (bidirectional, matches web).
            XCTAssertEqual(Set(host.legacySegments), ["premium", "newsletter", "sports_fan"])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testMergeLegacySegmentsNoOpWithoutMasterId() {
        let store = CdpSegmentsStore(defaults: defaults)
        let host = MockCdpHost(enabled: true, consent: true, account: 123, masterId: nil)
        host.legacySegments = ["sports_fan"]
        let manager = CdpManager(api: CdpApiClient(), host: host, segmentsStore: store)

        manager.mergeLegacySegments()

        let expectation = XCTestExpectation(description: "noop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // No master_id → nothing merged, legacy list untouched.
            XCTAssertEqual(host.legacySegments, ["sports_fan"])
            XCTAssertEqual(store.read(account: "123", masterId: LOCAL_MID_SENTINEL), [])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testGetCdpSegmentsEmptyWhenDisabled() {
        let store = CdpSegmentsStore(defaults: defaults)
        store.write(account: "123", masterId: LOCAL_MID_SENTINEL, value: ["x"])
        let manager = makeManager(enabled: false, masterId: nil, segmentsStore: store)
        XCTAssertEqual(manager.getCdpSegments(), [])
    }

    func testGetDataDisabledReturnsEmpty() {
        let store = CdpSegmentsStore(defaults: defaults)
        let manager = makeManager(enabled: false, masterId: "mid", segmentsStore: store)
        let data = manager.getData()
        XCTAssertNil(data.masterId)
        XCTAssertNil(data.rfv)
        XCTAssertEqual(data.cohorts, [])
    }
}
</content>
