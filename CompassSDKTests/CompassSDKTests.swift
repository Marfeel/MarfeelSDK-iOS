//
//  CompassSDKTests.swift
//  CompassSDKTests
//
//  Created by  on 14/01/2021.
//

import XCTest
@testable import CompassSDK

class MockOperation: Operation {
    private let trackInfo: TrackInfo
    
    init(trackInfo: TrackInfo) {
        self.trackInfo = trackInfo
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
        print(trackInfo.jsonEncode())
        runing = false
    }
}

class MockedOperationProvider: TikOperationFactory {
    func buildOperation(trackInfo: TrackInfo, dispatchDate: Date, scrollPercentProvider: ScrollPercentProvider?, conversionsProvider: ConversionsProvider?) -> Operation {
        MockOperation(trackInfo: trackInfo)
    }
}

class CompassSDKTests: XCTestCase {
    
    var timer: Timer?

    func testShouldSendTik() {
        let sut = CompassTracker(tikOperationFactory: MockedOperationProvider())
        let expectation = XCTestExpectation()
        sut.setSiteUserId("testUser1")
        sut.setUserType(.logged)
        sut.trackNewPage(url: URL(string: "http://localhost/test1")!)
        sut.trackConversion(conversion: "First conversion")
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false, block: { (timer) in
            sut.trackNewPage(url: URL(string: "http://localhost/test2")!)
            sut.trackConversion(conversion: "Second conversion")
        })
        
        wait(for: [expectation], timeout: 40)
    }

    func testShouldFetchRFV() {
        let sut = GetRFV()
        let expectation = XCTestExpectation()
        sut.fetch(userId: UUID().uuidString, account: 0) { (rfv, error) in
            guard error == nil else {
                XCTFail()
                return
            }
            
            XCTAssertNotNil(rfv)
            expectation.fulfill()
            print(rfv)
        }
        wait(for: [expectation], timeout: 40)
    }
}
