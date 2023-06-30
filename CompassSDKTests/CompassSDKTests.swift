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
        var expectation = XCTestExpectation()
                
        let operationProvider = MockedOperationProvider({ (data: Encodable) in
            let ingestData = data as! IngestTrackInfo
            
            XCTAssertEqual(ingestData.pageUrl, "http://localhost/test1")
            XCTAssertEqual(ingestData.siteUserId, "testUser1")
            XCTAssertEqual(ingestData.userType?.rawValue, 9)
            XCTAssertEqual(ingestData.userId, "userIdFromStorage")
            XCTAssertEqual(ingestData.sessionId, "sessionIdFromStorage")
            XCTAssertEqual(ingestData.sessionVars, ["session": "var"])
            XCTAssertEqual(ingestData.userVars, ["user": "var"])
            XCTAssertEqual(ingestData.pageVars, ["page": "var"])
            XCTAssertEqual(ingestData.userSegments, ["segment1", "segment2"])
            XCTAssertEqual(ingestData.pageType, 3)
            
            expectation.fulfill()
        })
        let sut = CompassTracker(storage: MockStorage(), tikOperationFactory: operationProvider)
        sut.setSiteUserId("testUser1")
        sut.setUserType(.custom(9))
        sut.trackNewPage(url: URL(string: "http://localhost/test1")!)
        sut.setPageVar(name: "page", value: "var")

        wait(for: [expectation], timeout: 5)
        
        expectation = XCTestExpectation()
        operationProvider.expectation = { (data) in
            let ingestData = data as! IngestTrackInfo
            
            XCTAssertEqual(ingestData.conversions, ["First conversion", "Second conversion"])
            XCTAssertEqual(ingestData.pageUrl, "http://localhost/test2")
            XCTAssertEqual(ingestData.siteUserId, "testUser1")
            XCTAssertEqual(ingestData.userType?.rawValue, 9)
            XCTAssertEqual(ingestData.userId, "userIdFromStorage")
            XCTAssertEqual(ingestData.sessionId, "sessionIdFromStorage")
            XCTAssertEqual(ingestData.sessionVars, ["session": "var"])
            XCTAssertEqual(ingestData.userVars, ["user": "var"])
            XCTAssertEqual(ingestData.pageVars, [String: String]())
            XCTAssertEqual(ingestData.userSegments, ["segment1", "segment2"])

            expectation.fulfill()
        }

        sut.trackNewPage(url: URL(string: "http://localhost/test2")!)
        sut.trackConversion(conversion: "First conversion")
        sut.trackConversion(conversion: "Second conversion")
        sut.setConsent(true)

        wait(for: [expectation], timeout: 5)
    }
    
    func testShouldFetchRFV() {
        let expectation = XCTestExpectation()
        let sut = GetRFV(apiRouter: MockApiRouterRfv(expect: {(apiCall) in
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
