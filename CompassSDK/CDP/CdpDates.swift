//
//  CdpDates.swift
//  CompassSDK
//
//  ISO-8601 helpers for meter dates. Mirrors CdpDates.kt.
//

import Foundation

private let isoParsers: [DateFormatter] = {
    let patterns = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
        "yyyy-MM-dd'T'HH:mm:ss'Z'"
    ]
    return patterns.map { pattern in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = pattern
        return formatter
    }
}()

private let isoFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return formatter
}()

internal func parseIsoDate(_ value: String?) -> Date? {
    guard let value = value, !value.isEmpty else { return nil }
    for parser in isoParsers {
        if let date = parser.date(from: value) {
            return date
        }
    }
    return nil
}

internal func formatIsoDate(_ date: Date?) -> String? {
    guard let date = date else { return nil }
    return isoFormatter.string(from: date)
}
