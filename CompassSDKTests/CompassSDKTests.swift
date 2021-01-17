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
        sut.startPageView(pageName: "Test ONE")
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false, block: { (timer) in
            sut.startPageView(pageName: "Test TWO")
        })
        
        wait(for: [expectation], timeout: 40)
    }

}
