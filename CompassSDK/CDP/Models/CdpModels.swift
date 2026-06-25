//
//  CdpModels.swift
//  CompassSDK
//
//  CDP identity / profile data models. Mirrors CdpModels.kt.
//  snake_case on the wire is handled via CodingKeys.
//

import Foundation

/// CDP Recency/Frequency/Value score. Distinct from the legacy `Rfv` (which uses
/// `rfv_r/f/v` keys and a Float score) — do not conflate the two.
public struct CdpRfv: Codable, Equatable {
    public let rfv: Int
    public let r: Int
    public let f: Int
    public let v: Int

    public init(rfv: Int, r: Int, f: Int, v: Int) {
        self.rfv = rfv
        self.r = r
        self.f = f
        self.v = v
    }
}

internal struct CdpIdentityResponse: Decodable {
    let masterId: String?
    let rfv: CdpRfv?
    let cohorts: [Int]

    enum CodingKeys: String, CodingKey {
        case masterId = "master_id"
        case rfv
        case cohorts
    }

    init(masterId: String?, rfv: CdpRfv?, cohorts: [Int]) {
        self.masterId = masterId
        self.rfv = rfv
        self.cohorts = cohorts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        masterId = try container.decodeIfPresent(String.self, forKey: .masterId)
        rfv = try? container.decodeIfPresent(CdpRfv.self, forKey: .rfv)
        cohorts = (try? container.decodeIfPresent([Int].self, forKey: .cohorts)) ?? []
    }
}

internal struct CdpCachedIdentity {
    let rfv: CdpRfv?
    let cohorts: [Int]
}

internal struct CdpResolveParams: Encodable {
    let siteId: Int
    let cookieId: String
    let masterId: String?

    enum CodingKeys: String, CodingKey {
        case siteId = "site_id"
        case cookieId = "cookie_id"
        case masterId = "master_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(siteId, forKey: .siteId)
        try container.encode(cookieId, forKey: .cookieId)
        try container.encodeIfPresent(masterId, forKey: .masterId)
    }
}

internal struct CdpLinkParams: Encodable {
    let siteId: Int
    let idType: String
    let idValue: String
    let isDeterministic: Bool
    let masterId: String?

    enum CodingKeys: String, CodingKey {
        case siteId = "site_id"
        case idType = "id_type"
        case idValue = "id_value"
        case isDeterministic = "is_deterministic"
        case masterId = "master_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(siteId, forKey: .siteId)
        try container.encode(idType, forKey: .idType)
        try container.encode(idValue, forKey: .idValue)
        try container.encode(isDeterministic, forKey: .isDeterministic)
        try container.encodeIfPresent(masterId, forKey: .masterId)
    }
}

internal struct CdpProfileUpdateParams: Encodable {
    let siteId: Int
    let masterId: String
    let properties: [String: String]?
    let segmentsAdd: [String]?
    let segmentsRemove: [String]?

    enum CodingKeys: String, CodingKey {
        case siteId = "site_id"
        case masterId = "master_id"
        case properties
        case segmentsAdd = "segments_add"
        case segmentsRemove = "segments_remove"
    }

    init(siteId: Int, masterId: String, properties: [String: String]? = nil, segmentsAdd: [String]? = nil, segmentsRemove: [String]? = nil) {
        self.siteId = siteId
        self.masterId = masterId
        self.properties = properties
        self.segmentsAdd = segmentsAdd
        self.segmentsRemove = segmentsRemove
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(siteId, forKey: .siteId)
        try container.encode(masterId, forKey: .masterId)
        // Absent fields are no-ops on the backend — omit, don't send empty.
        try container.encodeIfPresent(properties, forKey: .properties)
        try container.encodeIfPresent(segmentsAdd, forKey: .segmentsAdd)
        try container.encodeIfPresent(segmentsRemove, forKey: .segmentsRemove)
    }
}

/// CDP contribution to each tracking beacon. The JSON-string forms used on the beacon
/// are computed on demand rather than passed around as a flag.
public struct CdpData {
    public let masterId: String?
    public let rfv: CdpRfv?
    public let cohorts: [Int]

    public init(masterId: String?, rfv: CdpRfv?, cohorts: [Int]) {
        self.masterId = masterId
        self.rfv = rfv
        self.cohorts = cohorts
    }

    /// `{"rfv":42,"r":3,"f":5,"v":7}` or `""` when no RFV / on encoding failure.
    public var rfvSerialized: String {
        guard let rfv = rfv, let data = try? JSONEncoder().encode(rfv) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// `[101,204]` or `"[]"` on encoding failure.
    public var cohortsSerialized: String {
        guard let data = try? JSONEncoder().encode(cohorts) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
