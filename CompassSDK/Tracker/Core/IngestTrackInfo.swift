//
//  IngestTrackInfo.swift
//  CompassSDK
//
//  Created by Marc García Lopez on 28/04/2023.
//

import Foundation

struct IngestTrackInfo: Encodable {
    enum CodingKeys : String, CodingKey {
        case tik = "a"
        case visitDuration = "l"
        case scrollPercent = "sc"
        case implodedConversions = "conv"
        case landingPage = "lp"
        case cc = "cc"
        case recirculationSoruce = "rs"
    }
    
    private var trackInfo = TrackInfo()
    var tik = 0
    private var visitDuration: Int64?
    var conversions: [String]? {
        didSet {
            implodedConversions = conversions?.joined(separator: ",")
        }
    }
    var scrollPercent: Float?
    private var implodedConversions: String?
    
    var landingPage: String?
    var recirculationSource: String?
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try trackInfo.encode(to: encoder)
        try container.encodeIfPresent(tik, forKey: .tik)
        try container.encodeIfPresent(visitDuration, forKey: .visitDuration)
        try container.encodeIfPresent(scrollPercent, forKey: .scrollPercent)
        try container.encodeIfPresent(implodedConversions, forKey: .implodedConversions)
        try container.encodeIfPresent(landingPage, forKey: .landingPage)
        try container.encodeIfPresent(cc, forKey: .cc)
        try container.encodeIfPresent(recirculationSource, forKey: .recirculationSoruce)
    }
}

extension IngestTrackInfo {
    var pageUrl: String? {
        set {
            guard newValue != nil else {
                return
            }
            trackInfo.pageUrl = newValue
            scrollPercent = 0
        }
        get {
            trackInfo.pageUrl
        }
    }
    var accountId: Int? {
        set {
            trackInfo.accountId = newValue
        }
        get {
            trackInfo.accountId
        }
    }
    var currentDate: Date? {
        set {
            trackInfo.currentDate = newValue
            visitDuration = Int64((newValue?.timeStamp ?? 0) - (trackInfo.startPageTimeStamp ?? 0))
        }
        get {
            trackInfo.currentDate
        }
    }

    var currentVisitDate: Date? {
        set {
            trackInfo.currentVisitDate = newValue
        }
        get {
            trackInfo.currentDate
        }
    }

    var siteUserId: String? {
        set {
            trackInfo.siteUserId = newValue
        }
        get {
            trackInfo.siteUserId
        }
    }
    var compassVersion: String? {
        set {
            trackInfo.compassVersion = newValue
        }
        get {
            trackInfo.compassVersion
        }
    }
    var userId: String? {
        set {
            trackInfo.userId = newValue
        }
        get {
            trackInfo.userId
        }
    }
    var userType: UserType? {
        set {
            trackInfo.userType = newValue
        }
        get {
            trackInfo.userType
        }
    }
    
    var sessionId: String? {
        set {
            trackInfo.sessionId = newValue
        }
        get {
            trackInfo.sessionId
        }
    }
    var firstVisitDate: Date? {
        set {
            trackInfo.firstVisitDate = newValue
        }
        get {
            trackInfo.firstVisitDate
        }
    }
    var core: TrackInfo {
        get {
            trackInfo
        }
        set {
            trackInfo = newValue
        }
    }
    
    var userVars: Vars? {
        set {
            trackInfo.userVars = newValue
        }
        get {
            trackInfo.userVars
        }
    }
    
    var pageVars: Vars? {
        set {
            trackInfo.pageVars = newValue
        }
        get {
            trackInfo.pageVars
        }
    }
    
    var sessionVars: Vars? {
        set {
            trackInfo.sessionVars = newValue
        }
        get {
            trackInfo.sessionVars
        }
    }
    
    var userSegments: [String]? {
        set {
            trackInfo.userSegments = newValue
        }
        get {
            trackInfo.userSegments
        }
    }
    
    var pageType: Int? {
        set {
            trackInfo.pageType = newValue
        }
        get {
            trackInfo.pageType
        }
    }
    
    var hasConsent: Bool? {
        set {
            trackInfo.hasConsent = newValue
        }
        get {
            trackInfo.hasConsent
        }
    }
    
    var cc: Int {
        get {
            switch hasConsent {
            case true:
                return 1
            case false:
                return 0
            default:
                return 3
            }
        }
    }
}
