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
        let sut = CompassTracker.shared
        let expectation = XCTestExpectation()
        sut.setUserId("testUser1")
        sut.setUserType(.logged)
        sut.startPageView(url: URL(string: "http://localhost/test1")!)
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false, block: { (timer) in
            sut.startPageView(url: URL(string: "http://localhost/test2")!)
        })
        
        wait(for: [expectation], timeout: 40)
    }

}
