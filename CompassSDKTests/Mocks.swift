//
//  Mocks.swift
//  CompassSDKTests
//
//  Created by Marc García Lopez on 02/05/2023.
//

import Foundation
@testable import CompassSDK

typealias Expectation = (Encodable) -> ()

class MockOperation: Operation {
    private let dataBuilder: DataBuilder
    private let expectation: Expectation?

    init(
        dataBuilder: @escaping DataBuilder,
        expectation: Expectation? = nil
    ) {
        self.dataBuilder = dataBuilder
        self.expectation = expectation
    }
    
    private var runing: Bool = false {
        didSet {
            willChangeValue(forKey: "isFinished")
            willChangeValue(forKey: "isExecuting")
            didChangeValue(forKey: "isFinished")
            didChangeValue(forKey: "isExecuting")
        }
    }
    
    override var isAsynchronous: Bool {true}
    
    override var isFinished: Bool {!runing}
    
    override var isExecuting: Bool {runing}
    
    override func start() {
        let onData = { [self] (data: Encodable) in
            print(data.jsonEncode()!)
            runing = false

            expectation?(data)
        }
        dataBuilder(onData)
    }
}

class MockedOperationProvider: TikOperationFactory {
    var expectation: Expectation?
    
    init(_ expectation: Expectation? = nil) {
        self.expectation = expectation
    }
    
    func buildOperation(dataBuilder: @escaping DataBuilder, dispatchDate: Date, path: String?, contentType: ContentType?) -> Operation {
        MockOperation(dataBuilder: dataBuilder, expectation: expectation)
    }
}

class MockStorage: CompassStorage {
    var hasConsent: Bool?

    func setConsent(_ hasConsent: Bool) {
    }

    func addUserSegments(_ segments: [String]) {
    }

    var sessionVars = ["session": "var"]

    var userVars = ["user": "var"]

    var userSegments = ["segment1", "segment2"]

    func addSessionVar(name: String, value: String) {
    }

    func addUserVar(name: String, value: String) {
    }

    func addVisit() {
    }

    func addUserSegment(_ name: String) {
    }

    func removeUserSegment(_ name: String) {
    }

    func clearUserSegments() {
    }

    var userId = "userIdFromStorage"
    var sessionId = "sessionIdFromStorage"
    var suid: String? = "suidFromStorage"
    var firstVisit = Date()
    var lastVisit: Date? = nil
    var previousVisit: Date? = nil
    var sessionExpirationDate:Date? = nil
    var landingPage: String? = nil

    func setLandingPage(_ landingPage: String?) {
    }

    private var trackedConversions: [String] = []
    
    func shouldTrackConversion(_ conversion: String, id: String?) -> Bool {
        if id == nil {
            return true
        }

        let key = "\(conversion):\(id!)"

        return trackedConversions.contains(key) == false
    }

    func addTrackedConversion(_ conversion: String, id: String?) {
        if id != nil {
            trackedConversions.append("\(conversion):\(id!)")
        }
    }

    var cdpMasterId: String?
    var cdpRfv: String?
    var cdpCohorts: String?
    var cdpCacheSessionId: String?

    func readCdpMasterId() -> String? {
        guard let id = cdpMasterId, UUID(uuidString: id) != nil else { return nil }
        return id
    }

    func writeCdpMasterId(_ newMasterId: String) -> String? {
        let old = readCdpMasterId()
        cdpMasterId = newMasterId
        return old
    }

    func readCdpCachedIdentity(sessionId: String) -> CdpCachedIdentity? {
        guard cdpCacheSessionId == sessionId else { return nil }
        if cdpRfv == nil && cdpCohorts == nil { return nil }
        guard let json = cdpCohorts, let data = json.data(using: .utf8),
              let cohorts = try? JSONDecoder().decode([Int].self, from: data) else { return nil }
        let rfv = cdpRfv.flatMap { CdpRfv.jsonStringDecode(from: $0) }
        return CdpCachedIdentity(rfv: rfv, cohorts: cohorts)
    }

    func writeCdpCachedIdentity(rfv: CdpRfv?, cohorts: [Int], sessionId: String) {
        cdpRfv = rfv.flatMap { $0.encode() }.flatMap { String(data: $0, encoding: .utf8) }
        cdpCohorts = cohorts.encode().flatMap { String(data: $0, encoding: .utf8) }
        cdpCacheSessionId = sessionId
    }

    init() {}
}

class MockApiRouterRfv: ApiRouting {
    var expect: ((ApiCall) -> ())?
    
    init(expect: ((ApiCall) -> ())? = nil) {
        self.expect = expect
    }
    
    func request<T>(from apiCall: ApiCall, _ completion: @escaping (T?, Error?) -> ()) where T : Decodable {
        expect?(apiCall)
        
        let rfv = try? JSONDecoder().decode(T.self, from: "{\"rfv\": 1.1, \"r\": 1, \"f\": 2, \"v\": 3}".data(using: .utf8)!)
        completion(rfv, nil)
    }
    
    func call(from apiCall: ApiCall, _ completion: @escaping (Error?) -> ()) {}
}
