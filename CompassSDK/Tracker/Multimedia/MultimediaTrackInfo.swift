//
//  MultimediaTrackInfo.swift
//  CompassSDK
//
//  Created by Marc García Lopez on 27/04/2023.
//

import Foundation

struct MultimediaTrackInfo: Encodable {
    enum CodingKeys: String, CodingKey {
        case tik = "a"
    }
    
    var trackInfo: TrackInfo!
    var rfv: Rfv?
    let item: MultimediaItem!
    var tik = 0
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try trackInfo.encode(to: encoder)
        try rfv?.encode(to: encoder)
        try item.encode(to: encoder)
        try container.encode(tik, forKey: .tik)
    }
}
