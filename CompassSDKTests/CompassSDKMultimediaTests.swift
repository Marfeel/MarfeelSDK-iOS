//
//  CompassSDKMultimediaTests.swift
//  CompassSDKTests
//
//  Created by Marc García Lopez on 02/05/2023.
//

import XCTest
@testable import CompassSDK

class CompassSDKMultimediaTests: XCTestCase {
    
    var timer: Timer?
    
    func getTracker() -> CompassTracker {
        let operationProvider = MockedOperationProvider()
        
        return CompassTracker(
            storage: MockStorage(),
            tikOperationFactory: operationProvider,
            getRFV: GetRFV(apiRouter: MockApiRouterRfv())
        )
    }
    
    func testShouldSendTik() {
        let expectation = XCTestExpectation()
        let compassTracker = getTracker()
        
        compassTracker.setSiteUserId("testUser1")
        compassTracker.setUserType(.custom(9))
        compassTracker.trackNewPage(url: URL(string: "http://localhost/test1")!)
        
        var multimediaData:MultimediaTrackInfo!
        let compassTrackerMultimedia = CompassTrackerMultimedia(
            tikOperationFactory: MockedOperationProvider({ data in
                multimediaData = data as? MultimediaTrackInfo
                
                if (multimediaData.item.playbackInfo.ended) {
                    expectation.fulfill()
                }
            }),
            compassTracker: compassTracker
        )
        
        compassTrackerMultimedia.initializeItem(
            id: "test-id",
            provider: "test-provider",
            providerId: "test-provider-id",
            type: .VIDEO,
            metadata: MultimediaMetadata(
                title: "test-title",
                description: "test-description",
                url: "test-url",
                thumbnail: "test-thumbnail",
                authors: "test-authors",
                publishTime: "test-publishTime",
                duration: 123456
            )
        )
        
        compassTrackerMultimedia.registerEvent(id: "test-id", event: .PLAY, eventTime: 10)
        compassTrackerMultimedia.registerEvent(id: "test-id", event: .PAUSE, eventTime: 20)
        compassTrackerMultimedia.registerEvent(id: "test-id", event: .PLAY, eventTime: 30)
        compassTrackerMultimedia.registerEvent(id: "test-id", event: .MUTE, eventTime: 40)
        compassTrackerMultimedia.registerEvent(id: "test-id", event: .UNMUTE, eventTime: 50)
        compassTrackerMultimedia.registerEvent(id: "test-id", event: .AD_PLAY, eventTime: 60)
        compassTrackerMultimedia.registerEvent(id: "test-id", event: .AD_PLAY, eventTime: 65)
        compassTrackerMultimedia.registerEvent(id: "test-id", event: .PAUSE, eventTime: 70)
        compassTrackerMultimedia.registerEvent(id: "test-id", event: .END, eventTime: 123456)

        
        wait(for: [expectation], timeout: 5)
        
        XCTAssertEqual(multimediaData.trackInfo.pageUrl, "http://localhost/test1")
        XCTAssertEqual(multimediaData.trackInfo.siteUserId, "testUser1")
        XCTAssertEqual(multimediaData.trackInfo.userType?.rawValue, 9)
        XCTAssertEqual(multimediaData.trackInfo.userId, "userIdFromStorage")
        XCTAssertEqual(multimediaData.trackInfo.sessionId, "sessionIdFromStorage")
        XCTAssertEqual(multimediaData.item.id, "test-id")
        XCTAssertEqual(multimediaData.item.provider, "test-provider")
        XCTAssertEqual(multimediaData.item.providerId, "test-provider-id")
        XCTAssertEqual(multimediaData.item.type.rawValue, "video")
        XCTAssertEqual(
            String(decoding: multimediaData.item.playbackInfo.encode()!, as: UTF8.self),
            "{\"unmute\":[50],\"mute\":[40],\"ap\":2,\"mp\":123456,\"ads\":[60,65],\"fscr\":[],\"bscr\":[],\"a\":true,\"pause\":[20,70,123456],\"s\":true,\"play\":[10,30]}"
        )
        XCTAssertEqual(
            String(decoding: multimediaData.item.metadata.encode()!, as: UTF8.self),
            "{\"m_d\":\"test-description\",\"m_th\":\"test-thumbnail\",\"m_ti\":\"test-title\",\"m_il\":false,\"m_pt\":\"test-publishTime\",\"m_l\":123456,\"m_u\":\"test-url\",\"m_a\":\"test-authors\"}"
        )
    }
}
