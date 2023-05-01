//
//  TrackInfo.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation
    
struct TrackInfo: Encodable {
    enum CodingKeys : String, CodingKey {
        case pageUrl = "url"
        case accountId = "ac"
        case siteUserId = "sui"
        case userType = "ut"
        case startPageTimeStamp = "ps"
        case firstVisitTimeStamp = "fv"
        case currentTimeStamp = "n"
        case currentVisitTimeStamp = "t"
        case pageId = "p"
        case compassVersion = "v"
        case sessionId = "s"
        case previosPageUrl = "pp"
        case canonical = "c"
        case userId = "u"
        case pageType
    }

    var pageUrl: String? {
        didSet {
            if let oldValue = oldValue {
                previosPageUrl = oldValue
            }
            guard pageUrl != nil else {
                pageId = nil
                return
            }
            pageId = UUID().uuidString
            pagesViewed += 1
            startPageDate = Date()
        }
    }
    var accountId: Int?
    var firstVisitDate: Date?
    var currentDate: Date?
    var currentVisitDate: Date?
    var siteUserId: String?
    var compassVersion: String?
    var userId: String?
    var userType: UserType?
    let pageType = 3
    var startPageTimeStamp: Int64? {
        return startPageDate?.timeStamp
    }
    var firstVisitTimeStamp: Int64? {
        return firstVisitDate?.timeStamp
    }
    var currentTimeStamp: Int64? {
        return currentDate?.timeStamp
    }
    var currentVisitTimeStamp: Int64? {
        return currentVisitDate?.timeStamp
    }
    var canonical: String? {
        return pageUrl
    }
    var sessionId: String?
    private var pagesViewed = 0
    private var pageId: String?
    private var previosPageUrl: String?
    private var startPageDate: Date?
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(pageUrl, forKey: .pageUrl)
        try container.encode(accountId, forKey: .accountId)
        try container.encode(siteUserId, forKey: .siteUserId)
        try container.encode(userType, forKey: .userType)
        try container.encode(startPageTimeStamp, forKey: .startPageTimeStamp)
        try container.encode(firstVisitTimeStamp, forKey: .firstVisitTimeStamp)
        try container.encode(pageId, forKey: .pageId)
        try container.encode(compassVersion, forKey: .compassVersion)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(previosPageUrl, forKey: .previosPageUrl)
        try container.encode(canonical, forKey: .canonical)
        try container.encode(userId, forKey: .userId)
        try container.encode(pageType, forKey: .pageType)
    }
}
