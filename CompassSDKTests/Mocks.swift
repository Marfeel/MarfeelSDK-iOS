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
        let data = dataBuilder(onData)
        
        guard data != nil else {
            return
        }
        
        onData(data!)
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
    var sessionVars = ["session": "var"]
    
    var userVars = ["user": "var"]
    
    func addSessionVar(name: String, value: String) {
    }
    
    func addUserVar(name: String, value: String) {
    }
    
    func addVisit() {
    }
    
    var userId = "userIdFromStorage"
    var sessionId = "sessionIdFromStorage"
    var suid: String? = "suidFromStorage"
    var firstVisit = Date()
    var lastVisit: Date? = nil
    var previousVisit: Date? = nil
    var sessionExpirationDate:Date? = nil
    
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
