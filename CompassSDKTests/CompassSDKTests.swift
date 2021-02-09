//
//  CompassSDKTests.swift
//  CompassSDKTests
//
//  Created by  on 14/01/2021.
//

import XCTest
@testable import CompassSDK

class CompassSDKTests: XCTestCase {
    
    var timer: Timer?

    func testShouldSendTik() {
        let sut = CompassTracker(bundle: Bundle.init(for: CompassSDKTests.self))
        let expectation = XCTestExpectation()
        sut.setUserId("testUser1")
        sut.setUserType(.logged)
        sut.startPageView(url: URL(string: "http://localhost/test1")!)
        sut.track(conversion: "First conversion")
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false, block: { (timer) in
            sut.startPageView(url: URL(string: "http://localhost/test2")!)
            sut.track(conversion: "Second conversion")
        })
        
        wait(for: [expectation], timeout: 40)
    }

    func testShouldFetchRFV() {
        let sut = GetRFV(compassEndpoint: "https://events.newsroom.bi/")
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
