//
//  ConversionTrackingTests.swift
//  CompassSDKTests
//

import XCTest
@testable import CompassSDK

/// Records every beacon and answers it as `respond` decides; `nil` holds the answer until
/// `release` is called, leaving the beacon in flight.
private final class ScriptedSendTik: SendTikCuseCase {
    struct Beacon {
        let params: [String: Any]
        var conversion: String? { params["conv"] as? String }
        var url: String? { params["url"] as? String }
        var pageId: String? { params["p"] as? String }
        var tick: Int? { params["a"] as? Int }
    }

    private let lock = NSLock()
    private var _beacons = [Beacon]()
    private var held = [(Bool) -> Void]()
    var respond: (Beacon) -> Bool? = { _ in true }
    var onBeacon: ((Beacon) -> Void)?

    var beacons: [Beacon] {
        lock.lock()
        defer { lock.unlock() }
        return _beacons
    }

    func tik(path: String, type: ContentType, params: [String: Any], completion: @escaping (Bool) -> Void) {
        let beacon = Beacon(params: params)
        lock.lock()
        _beacons.append(beacon)
        let answer = respond(beacon)
        if answer == nil { held.append(completion) }
        lock.unlock()

        if let answer = answer { completion(answer) }
        onBeacon?(beacon)
    }

    func release(sent: Bool) {
        lock.lock()
        let completions = held
        held.removeAll()
        lock.unlock()
        completions.forEach { $0(sent) }
    }
}

/// Real `TikOperation`s, fired almost at once instead of after the tracker's deadline.
private final class FastTikOperationProvider: TikOperationFactory {
    let sendTik: ScriptedSendTik

    init(sendTik: ScriptedSendTik) {
        self.sendTik = sendTik
    }

    func buildOperation(dataBuilder: @escaping DataBuilder, dispatchDate: Date, path: String?, contentType: ContentType?) -> Operation {
        TikOperation(dataBuilder: dataBuilder, dispatchDate: Date(timeIntervalSinceNow: 0.05), tikUseCase: sendTik, path: path, contentType: contentType)
    }
}

private struct Payload: Encodable {
    let value: String
}

class TikOperationTests: XCTestCase {
    private let queue = OperationQueue()

    func testSendsEveryPayloadAndReportsItsResult() {
        let sendTik = ScriptedSendTik()
        sendTik.respond = { $0.params["value"] as? String == "a" }
        let results = expectation(description: "results")
        results.expectedFulfillmentCount = 2
        var sent = [String: Bool]()

        let operation = TikOperation(dataBuilder: { completion in
            completion([
                TikPayload(data: Payload(value: "a")) { sent["a"] = $0; results.fulfill() },
                TikPayload(data: Payload(value: "b")) { sent["b"] = $0; results.fulfill() },
            ])
        }, dispatchDate: Date(), tikUseCase: sendTik, path: "ingest.php", contentType: .FORM)
        queue.addOperation(operation)

        wait(for: [results], timeout: 2)
        XCTAssertEqual(sent, ["a": true, "b": false])
        XCTAssertEqual(sendTik.beacons.count, 2)
    }

    func testPayloadsBuiltAfterCancellingAreReportedUnsent() {
        let sendTik = ScriptedSendTik()
        let building = expectation(description: "building")
        let result = expectation(description: "result")
        var pending: DataBuilderCompletion?
        var sent: Bool?

        let operation = TikOperation(dataBuilder: { completion in
            pending = completion
            building.fulfill()
        }, dispatchDate: Date(), tikUseCase: sendTik, path: "ingest.php", contentType: .FORM)
        queue.addOperation(operation)
        wait(for: [building], timeout: 2)

        operation.cancel()
        pending?([TikPayload(data: Payload(value: "a")) { sent = $0; result.fulfill() }])

        wait(for: [result], timeout: 2)
        XCTAssertEqual(sent, false)
        XCTAssertTrue(sendTik.beacons.isEmpty)
    }
}

class ConversionTrackingTests: XCTestCase {
    private var sendTik: ScriptedSendTik!
    private var storage: MockStorage!
    private var sut: CompassTracker!

    override func setUp() {
        super.setUp()
        sendTik = ScriptedSendTik()
        storage = MockStorage()
        sut = CompassTracker(storage: storage, tikOperationFactory: FastTikOperationProvider(sendTik: sendTik))
    }

    override func tearDown() {
        sut.stopTracking()
        sendTik.release(sent: true)
        sut = nil
        super.tearDown()
    }

    /// Spins the main run loop, which beacons are built on, until `condition` holds.
    private func waitUntil(_ description: String, timeout: TimeInterval = 3, _ condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        XCTAssertTrue(condition(), description)
    }

    private func waitForMoreTiks(_ count: Int = 3) {
        let seen = sendTik.beacons.count
        waitUntil("\(count) more tiks") { sendTik.beacons.count >= seen + count }
    }

    private func conversionBeacons(_ name: String) -> [ScriptedSendTik.Beacon] {
        sendTik.beacons.filter { $0.conversion == name }
    }

    func testFailedConversionIsRetriedAndOnlyMarkedTrackedOnceSent() {
        var attempts = 0
        sendTik.respond = { beacon in
            guard beacon.conversion == "purchase" else { return true }
            attempts += 1
            return attempts > 1
        }

        sut.trackNewPage(url: URL(string: "http://localhost/paywall")!)
        sut.trackConversion(conversion: "purchase", options: ConversionOptions(id: "tx1"))

        waitUntil("first attempt") { conversionBeacons("purchase").count == 1 }
        XCTAssertTrue(storage.shouldTrackConversion("purchase", id: "tx1"))

        waitUntil("retry") { conversionBeacons("purchase").count == 2 }
        waitUntil("marked as tracked") { !storage.shouldTrackConversion("purchase", id: "tx1") }

        waitForMoreTiks()
        XCTAssertEqual(conversionBeacons("purchase").count, 2)
    }

    func testSameConversionIdIsSentOnceWhilePending() {
        sendTik.respond = { $0.conversion == nil ? true : nil }

        sut.trackNewPage(url: URL(string: "http://localhost/paywall")!)
        sut.trackConversion(conversion: "purchase", options: ConversionOptions(id: "tx1"))
        sut.trackConversion(conversion: "purchase", options: ConversionOptions(id: "tx1"))

        waitUntil("conversion in flight") { conversionBeacons("purchase").count == 1 }
        waitForMoreTiks()

        XCTAssertEqual(conversionBeacons("purchase").count, 1)
        XCTAssertEqual(sendTik.beacons.last?.params["pvar"] as? [[String]], [["ios-duplicatedConversion", "purchase:tx1"]])
    }

    func testConversionLeftInFlightByAPageChangeIsSentWithItsOwnPage() {
        sendTik.respond = { $0.conversion == nil ? true : nil }

        sut.trackNewPage(url: URL(string: "http://localhost/paywall")!)
        sut.setPageVar(name: "step", value: "paywall")
        sut.trackConversion(conversion: "purchase", options: ConversionOptions(id: "tx1"))
        waitUntil("conversion in flight") { conversionBeacons("purchase").count == 1 }
        let first = conversionBeacons("purchase")[0]

        sut.trackNewPage(url: URL(string: "http://localhost/home")!)
        sendTik.respond = { _ in true }
        sendTik.release(sent: false)

        waitUntil("conversion resent") { conversionBeacons("purchase").count == 2 }
        let resent = conversionBeacons("purchase")[1]

        XCTAssertEqual(resent.url, "http://localhost/paywall")
        XCTAssertEqual(resent.pageId, first.pageId)
        XCTAssertEqual(resent.params["pvar"] as? [[String]], [["step", "paywall"]])
        XCTAssertGreaterThan(resent.tick ?? 0, first.tick ?? 0)
        XCTAssertEqual(resent.params["ps"] as? Int, first.params["ps"] as? Int)
        XCTAssertLessThanOrEqual(resent.params["l"] as? Int ?? .max, 1)

        waitForMoreTiks()
        let home = sendTik.beacons.filter { $0.url == "http://localhost/home" }
        XCTAssertEqual(home.first?.tick, 0)
        XCTAssertTrue(home.allSatisfy { $0.conversion == nil })
        XCTAssertNotEqual(home.first?.pageId, first.pageId)
        XCTAssertEqual(conversionBeacons("purchase").count, 2)
    }

    func testConversionPendingWhenThePageChangesIsSentWithItsOwnPage() {
        sendTik.respond = { $0.conversion == nil ? true : false }

        sut.trackNewPage(url: URL(string: "http://localhost/paywall")!)
        sut.trackConversion(conversion: "purchase")
        waitUntil("failed attempt") { conversionBeacons("purchase").count >= 1 }

        var delivered = [ScriptedSendTik.Beacon]()
        sendTik.respond = { beacon in
            if beacon.conversion != nil { delivered.append(beacon) }
            return true
        }
        sut.trackNewPage(url: URL(string: "http://localhost/home")!)

        waitUntil("sent from the next page") { delivered.count == 1 }
        XCTAssertEqual(delivered.first?.url, "http://localhost/paywall")

        waitForMoreTiks()
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(sendTik.beacons.last?.url, "http://localhost/home")
    }
}
