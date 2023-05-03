//
//  MultimediaMetadata.swift
//  CompassSDK
//
//  Created by Marc García Lopez on 27/04/2023.
//

import Foundation

public struct MultimediaMetadata: Codable {
    private enum CodingKeys : String, CodingKey {
        case isLive = "m_il"
        case title = "m_ti"
        case description = "m_d"
        case url = "m_u"
        case thumbnail = "m_th"
        case authors = "m_a"
        case publishTime = "m_pt"
        case duration = "m_l"
    }

    var isLive = false
    var title: String?
    var description: String?
    var url: String?
    var thumbnail: String?
    var authors: String?
    var publishTime: Int64?
    var duration: Int?
    
    public init(
        isLive: Bool = false,
        title: String? = nil,
        description: String? = nil,
        url: URL? = nil,
        thumbnail: URL? = nil,
        authors: String? = nil,
        publishTime: Date? = nil,
        duration: Int? = nil
    ) {
        self.isLive = isLive
        self.title = title
        self.description = description
        self.url = url?.absoluteString
        self.thumbnail = thumbnail?.absoluteString
        self.authors = authors
        self.publishTime = publishTime?.timeStamp
        self.duration = duration
    }
}
