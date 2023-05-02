//
//  CompassSDKTests.swift
//  CompassSDKTests
//
//  Created by  on 14/01/2021.
//

import XCTest
@testable import CompassSDK

fileprivate typealias Expectation = (IngestTrackInfo) -> ()

class MockOperation: Operation {
    private let dataBuilder: DataBuilder
    private let expectation: Expectation?

    fileprivate init(dataBuilder: @escaping DataBuilder, expectation: Expectation?) {
        self.dataBuilder = dataBuilder
        self.expectation =  expectation
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
            
            expectation?(data as! IngestTrackInfo)
        }
        let data = dataBuilder(onData)
        
        guard data != nil else {
            return
        }
        
        onData(data!)
    }
}

class MockedOperationProvider: TikOperationFactory {
    fileprivate var expectation: Expectation?
    
    fileprivate init(expectation: Expectation?) {
        self.expectation = expectation
    }
    
    func buildOperation(dataBuilder: @escaping DataBuilder, dispatchDate: Date, path: String?, contentType: ContentType?) -> Operation {
        MockOperation(dataBuilder: dataBuilder, expectation: expectation)
    }
}

class MockStorage: CompassStorage {
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

class MockApiRouter: ApiRouting {
    var expect: (ApiCall) -> ()
    
    init(expect: @escaping (ApiCall) -> ()) {
        self.expect = expect
    }
    
    func request<T>(from apiCall: ApiCall, _ completion: @escaping (T?, Error?) -> ()) where T : Decodable {
        expect(apiCall)
        
        let rfv = try? JSONDecoder().decode(T.self, from: "{\"rfv\": 1.1, \"r\": 1, \"f\": 2, \"v\": 3}".data(using: .utf8)!)
        completion(rfv, nil)
    }
    
    func call(from apiCall: ApiCall, _ completion: @escaping (Error?) -> ()) {}
}

class CompassSDKTests: XCTestCase {
    
    var timer: Timer?

    func testShouldSendTik() {
        var expectation = XCTestExpectation()
                
        let operationProvider = MockedOperationProvider(expectation: { (data: IngestTrackInfo) in
            XCTAssertEqual(data.pageUrl, "http://localhost/test1")
            XCTAssertEqual(data.siteUserId, "testUser1")
            XCTAssertEqual(data.userType?.rawValue, 9)
            XCTAssertEqual(data.userId, "userIdFromStorage")
            XCTAssertEqual(data.sessionId, "sessionIdFromStorage")

            expectation.fulfill()
        })
        let sut = CompassTracker(storage: MockStorage(), tikOperationFactory: operationProvider)
        sut.setSiteUserId("testUser1")
        sut.setUserType(.custom(9))
        sut.trackNewPage(url: URL(string: "http://localhost/test1")!)
        
        wait(for: [expectation], timeout: 5)
        
        expectation = XCTestExpectation()
        operationProvider.expectation = { (data) in
            XCTAssertEqual(data.conversions, ["First conversion", "Second conversion"])
            XCTAssertEqual(data.pageUrl, "http://localhost/test2")
            XCTAssertEqual(data.siteUserId, "testUser1")
            XCTAssertEqual(data.userType?.rawValue, 9)
            XCTAssertEqual(data.userId, "userIdFromStorage")
            XCTAssertEqual(data.sessionId, "sessionIdFromStorage")

            expectation.fulfill()
        }

        sut.trackNewPage(url: URL(string: "http://localhost/test2")!)
        sut.trackConversion(conversion: "First conversion")
        sut.trackConversion(conversion: "Second conversion")
        
        wait(for: [expectation], timeout: 5)
    }

    func testShouldFetchRFV() {
        let expectation = XCTestExpectation()
        let sut = GetRFV(apiRouter: MockApiRouter(expect: {(apiCall) in
            XCTAssertEqual(apiCall.path, "data.php")
            XCTAssertEqual(apiCall.type.rawValue, ContentType.FORM.rawValue)
            XCTAssertEqual(apiCall.params["u"] as! String, "uuid")
            XCTAssertEqual(apiCall.params["ac"] as! Int, 0)
        }))
        sut.fetch(userId: "uuid", account: 0) { (rfv, error) in
            guard error == nil else {
                XCTFail()
                return
            }
            
            XCTAssertEqual(rfv?.rfv, 1.1)
            XCTAssertEqual(rfv?.r, 1)
            XCTAssertEqual(rfv?.f, 2)
            XCTAssertEqual(rfv?.v, 3)
            
            expectation.fulfill()
            print(rfv)
        }
        wait(for: [expectation], timeout: 5)
    }
}
