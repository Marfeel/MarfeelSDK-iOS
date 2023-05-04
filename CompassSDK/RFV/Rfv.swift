//
//  Rfv.swift
//  CompassSDK
//
//  Created by Marc García Lopez on 28/04/2023.
//

import Foundation

public struct Rfv: Codable {
    enum EncodingKeys: String, CodingKey {
        case rfv = "rfv"
        case r = "rfv_r"
        case f = "rfv_f"
        case v = "rfv_v"
    }
    
    enum DecodingKeys: String, CodingKey {
        case rfv
        case r
        case f
        case v
    }
    
    let rfv: Float
    let r: Int
    let f: Int
    let v: Int
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: DecodingKeys.self)
        
        rfv = try values.decode(Float.self, forKey: .rfv)
        r = try values.decode(Int.self, forKey: .r)
        f = try values.decode(Int.self, forKey: .f)
        v = try values.decode(Int.self, forKey: .v)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)
        
        try container.encodeIfPresent(rfv, forKey: .rfv)
        try container.encodeIfPresent(r, forKey: .r)
        try container.encodeIfPresent(f, forKey: .f)
        try container.encodeIfPresent(v, forKey: .v)
    }
}
