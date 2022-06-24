//
//  TrackInfo.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

struct TrackInfo: Codable {
    private enum CodingKeys : String, CodingKey {
        case
            pageUrl = "url",
            accountId = "ac",
            tik = "a",
            userId = "sui",
            userType = "ut",
            startPageTimeStamp = "ps",
            firstVisitTimeStamp = "fv",
            currentTimeStamp = "n",
            visitDuration = "l",
            currentVisitTimeStamp = "t",
            pageId = "p",
            compassVersion = "v",
            sessionId = "s",
            scrollPercent = "sc",
            previosPageUrl = "pp",
            canonical = "c",
            siteUserId = "u",
            implodedConversions = "conv",
            pageType
    }
    
    var pageUrl: String? {
        didSet {
            canonical = pageUrl
            if let oldValue = oldValue {
                previosPageUrl = oldValue
            }
            guard pageUrl != nil else {
                pageId = nil
                return
            }
            pageId = UUID().uuidString
            tik = 0
            pagesViewed += 1
            startPageDate = Date()
        }
    }
    var accountId: Int?
    var tik = 0
    var conversions: [String]? {
        didSet {
            implodedConversions = conversions?.joined(separator: ",")
        }
    }
    
    private var startPageDate: Date? {
        didSet {
            startPageTimeStamp = startPageDate?.timeStamp
        }
    }
    
    var fisrtVisitDate: Date? {
        didSet {
            firstVisitTimeStamp = fisrtVisitDate?.timeStamp
        }
    }
    
    var currentDate: Date? {
        didSet {
            currentTimeStamp = currentDate?.timeStamp
        }
    }
    
    var currentVisitDate: Date? {
        didSet {
            currentVisitTimeStamp = currentVisitDate?.timeStamp
        }
    }
    
    var siteUserId: String?
    var compassVersion: String?
    var scrollPercent: Float?
    var userId: String?
    var userType: UserType?
    let pageType = 3
    
    private var pagesViewed = 0
    
    private var pageId: String?
    private var startPageTimeStamp: Int64?
    private var firstVisitTimeStamp: Int64?
    private var currentTimeStamp: Int64? {
        didSet {
            visitDuration = Int64(((currentTimeStamp ?? 0) - (startPageTimeStamp ?? 0)) / 1000)
        }
    }
    private var currentVisitTimeStamp: Int64?
    private var visitDuration: Int64?
    var sessionId: String?
    private var previosPageUrl: String?
    private var canonical: String?
    private var implodedConversions: String?
}

extension TrackInfo {
    var params: [String: Any] {
        self.jsonEncode()!
    }
    
    var data: Data {
        self.encode()!
    }
}
