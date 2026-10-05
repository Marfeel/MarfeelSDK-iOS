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

/// Wire shape shared by `/resolve/`, `/link/`, `/update/` and `/delete/`.
///
/// `segments` are the Server Segments the CDP asserts for this master; `properties` the
/// Server Properties it computed. Both are absent on older servers and on the fail-open
/// `UNKNOWN_CDP_IDENTITY`.
internal struct CdpIdentityResponse: Equatable {
    let masterId: String?
    let rfv: CdpRfv?
    let cohorts: [Int]
    let segments: [String]?
    let properties: [String: String]?

    init(masterId: String?, rfv: CdpRfv?, cohorts: [Int], segments: [String]? = nil, properties: [String: String]? = nil) {
        self.masterId = masterId
        self.rfv = rfv
        self.cohorts = cohorts
        self.segments = segments
        self.properties = properties
    }

    /// Hand-rolled so a non-string server property (`{"age": 42}`) is coerced instead of
    /// failing the whole response into `UNKNOWN_CDP_IDENTITY`. Nil when the body is not
    /// a JSON object.
    static func decode(from data: Data) -> CdpIdentityResponse? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return parse(json: root)
    }

    static func parse(json root: [String: Any]) -> CdpIdentityResponse {
        let rfv = (root["rfv"] as? [String: Any]).flatMap { raw -> CdpRfv? in
            guard let rfv = cdpInt(raw["rfv"]), let r = cdpInt(raw["r"]), let f = cdpInt(raw["f"]), let v = cdpInt(raw["v"]) else { return nil }
            return CdpRfv(rfv: rfv, r: r, f: f, v: v)
        }
        let cohorts = (root["cohorts"] as? [Any])?.compactMap { cdpInt($0) } ?? []
        let segments = (root["segments"] as? [Any])?.compactMap { $0 as? String }
        let properties = (root["properties"] as? [String: Any]).map { cdpStringValues($0) }

        return CdpIdentityResponse(
            masterId: root["master_id"] as? String,
            rfv: rfv,
            cohorts: cohorts,
            segments: segments,
            properties: properties
        )
    }
}

/// `/cdp/identity/delete/` answer: the identity shape plus a count (0 when nothing was owned).
internal struct CdpDeleteResponse {
    let identity: CdpIdentityResponse
    let deleted: Int
}

/// `/cdp/identity/reset/` answer. `cleared` lists the cookies actually presented.
public struct CdpResetResponse: Equatable {
    public let reset: Bool
    public let siteId: Int?
    public let cleared: [String]
}

/// Locally-cached read-only identity payload (rfv + cohorts).
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

/// `/cdp/identity/delete/` body. A nil `idValue` is **omitted entirely** from the JSON
/// (never sent as `null`/`""`): that form unlinks every identity of `idType` the master owns.
internal struct CdpDeleteParams: Encodable {
    let siteId: Int
    let masterId: String
    let idType: String
    let idValue: String?

    enum CodingKeys: String, CodingKey {
        case siteId = "site_id"
        case masterId = "master_id"
        case idType = "id_type"
        case idValue = "id_value"
    }

    init(siteId: Int, masterId: String, idType: String, idValue: String? = nil) {
        self.siteId = siteId
        self.masterId = masterId
        self.idType = idType
        self.idValue = idValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(siteId, forKey: .siteId)
        try container.encode(masterId, forKey: .masterId)
        try container.encode(idType, forKey: .idType)
        try container.encodeIfPresent(idValue, forKey: .idValue)
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
///
/// `identityFresh` is true only when *this* process actually round-tripped an identity
/// call that returned a master_id (resolve or link) — a warm cache never counts. Sent to
/// ingest as `cdp_fresh`.
public struct CdpData {
    public let masterId: String?
    public let rfv: CdpRfv?
    public let cohorts: [Int]
    public let identityFresh: Bool

    public init(masterId: String?, rfv: CdpRfv?, cohorts: [Int], identityFresh: Bool = false) {
        self.masterId = masterId
        self.rfv = rfv
        self.cohorts = cohorts
        self.identityFresh = identityFresh
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

// MARK: - JSON coercion helpers

/// Coerces every value of a JSON object to a string (`42` → `"42"`, `true` → `"true"`,
/// nested containers → their JSON text); `null` entries are dropped.
internal func cdpStringValues(_ source: [String: Any]) -> [String: String] {
    var out: [String: String] = [:]
    for (key, value) in source {
        if value is NSNull { continue }
        if let string = value as? String {
            out[key] = string
        } else if let number = value as? NSNumber {
            out[key] = cdpNumberString(number)
        } else if let data = try? JSONSerialization.data(withJSONObject: value), let text = String(data: data, encoding: .utf8) {
            out[key] = text
        } else {
            out[key] = String(describing: value)
        }
    }
    return out
}

private func cdpNumberString(_ number: NSNumber) -> String {
    // JSON booleans arrive as NSNumber; keep them textual, not 0/1.
    if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
    return number.stringValue
}
