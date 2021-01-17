//
//  TrackInfo.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

struct TrackInfo: Codable {
    var pageUrl: String? {
        didSet {
            guard pageUrl != nil else {
                pageId = nil
                return
            }
            pageId = UUID().uuidString
        }
    }
    var accountId: String?
    var tik = 0
    var conversions = [CompassConversionEvent]()
    var user: CompassUser?
    var pagesViewed = 0
    private var pageId: String?
}
