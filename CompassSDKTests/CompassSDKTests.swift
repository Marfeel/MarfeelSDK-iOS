//
//  CompassSDKTests.swift
//  CompassSDKTests
//
//  Created by  on 14/01/2021.
//

import XCTest
@testable import CompassSDK


class CompassSDKTests: XCTestCase {
    
    

    func testShouldSendTik() {
        let sut = CompassTracker()
        let expectation = XCTestExpectation()
        sut.startPageView(pageName: "Test page")
        wait(for: [expectation], timeout: 30)
    }

}
