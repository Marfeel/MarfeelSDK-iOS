//
//  MeterState.swift
//  CompassSDK
//
//  Server-authoritative meter (metered paywall) models. Mirrors MeterState.kt.
//

import Foundation

public struct MeterWindow: Equatable {
    public let duration: String
    public let period: String
    public let tz: String

    public init(duration: String = "", period: String = "", tz: String = "") {
        self.duration = duration
        self.period = period
        self.tz = tz
    }
}

public struct MeterState: Equatable {
    public let name: String
    public let count: Int
    /// Present only when the meter has a threshold configured. Preserve absent-vs-present.
    public let threshold: Int?
    public let reached: Bool?
    public let remaining: Int?
    public let startedAt: Date?
    public let expiresAt: Date?
    public let window: MeterWindow

    public init(name: String, count: Int = 0, threshold: Int? = nil, reached: Bool? = nil, remaining: Int? = nil, startedAt: Date? = nil, expiresAt: Date? = nil, window: MeterWindow = MeterWindow()) {
        self.name = name
        self.count = count
        self.threshold = threshold
        self.reached = reached
        self.remaining = remaining
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.window = window
    }
}

/// Thrown/surfaced when an increment targets a meter not configured for the site (HTTP 404).
public struct MeterNotFoundError: Error {
    public let meterName: String
    public init(meterName: String) { self.meterName = meterName }
}

extension MeterState {
    /// Parse a raw meter object (snake_case wire shape) into a normalized `MeterState`.
    /// The `threshold`/`reached`/`remaining` trio is present only when `threshold` exists.
    static func from(json raw: [String: Any]) -> MeterState {
        let windowJson = raw["window"] as? [String: Any]
        let window = MeterWindow(
            duration: windowJson?["duration"] as? String ?? "",
            period: windowJson?["period"] as? String ?? "",
            tz: windowJson?["tz"] as? String ?? ""
        )

        let hasThreshold = raw["threshold"] != nil && !(raw["threshold"] is NSNull)

        return MeterState(
            name: raw["name"] as? String ?? "",
            count: cdpInt(raw["count"]) ?? 0,
            threshold: hasThreshold ? cdpInt(raw["threshold"]) : nil,
            reached: hasThreshold ? (cdpBool(raw["reached"]) ?? false) : nil,
            remaining: hasThreshold ? (cdpInt(raw["remaining"]) ?? 0) : nil,
            startedAt: parseIsoDate(raw["started_at"] as? String),
            expiresAt: parseIsoDate(raw["expires_at"] as? String),
            window: window
        )
    }

    /// JSON-compatible dictionary for persistence (dates serialized to ISO strings).
    func toJson() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "count": count,
            "window": [
                "duration": window.duration,
                "period": window.period,
                "tz": window.tz
            ]
        ]
        if let threshold = threshold { dict["threshold"] = threshold }
        if let reached = reached { dict["reached"] = reached }
        if let remaining = remaining { dict["remaining"] = remaining }
        if let startedAt = formatIsoDate(startedAt) { dict["started_at"] = startedAt }
        if let expiresAt = formatIsoDate(expiresAt) { dict["expires_at"] = expiresAt }
        return dict
    }
}

private func cdpInt(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    if let int = value as? Int { return int }
    if let string = value as? String { return Int(string) }
    return nil
}

private func cdpBool(_ value: Any?) -> Bool? {
    if let number = value as? NSNumber { return number.boolValue }
    if let bool = value as? Bool { return bool }
    return nil
}
