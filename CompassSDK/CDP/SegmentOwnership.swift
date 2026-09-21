//
//  SegmentOwnership.swift
//  CompassSDK
//
//  Read-time rules for combining device-owned segments / vars with the Server Segments /
//  Server Properties the CDP asserts. The two sides are **never merged in storage** —
//  only here, when read back or sent — so the bulk device paths (`setUserSegments`,
//  `clearUserSegments`) can only ever name locally-asserted keys in `segments_remove`.
//

import Foundation

internal enum SegmentOwnership {

    /// Union, **server first**, deduplicated, untrimmed. Server-first is what makes
    /// `trimSegments` drop device-owned segments before server ones.
    static func mergeSegments(owned: [String]?, server: [String]?) -> [String] {
        var seen = Set<String>()
        return ((server ?? []) + (owned ?? [])).filter { seen.insert($0).inserted }
    }

    /// Bulk replace is the one shape where intent is ambiguous — an echo of
    /// `getUserSegments()` and a deliberate assertion are byte-identical. A backend-owned
    /// key let through would later be posted as `segments_remove` by `clearUserSegments`,
    /// deleting a membership this device never asserted. Keys already owned stay: the
    /// device owns them regardless of what the backend also knows.
    static func rejectUnownedSegments(requested: [String], owned: [String]?, server: [String]?) -> [String] {
        guard let server = server, !server.isEmpty else { return requested }
        let ownedSet = Set(owned ?? [])
        let unowned = Set(server.filter { !ownedSet.contains($0) })

        return requested.filter { segment in
            let keep = !unowned.contains(segment)
            if !keep { warnUnownedSegment(segment) }
            return keep
        }
    }

    /// Strict: exactly `MAX_SENT_SEGMENTS` is fine.
    static func isOverSegmentLimit(_ segments: [String]) -> Bool { segments.count > MAX_SENT_SEGMENTS }

    static func trimSegments(_ segments: [String]) -> [String] {
        return segments.count <= MAX_SENT_SEGMENTS ? segments : Array(segments.prefix(MAX_SENT_SEGMENTS))
    }

    /// Device-owned vars first, then every server property whose key the device does
    /// not own. Device-owned wins on a collision.
    static func mergeVars(owned: [String: String]?, server: [String: String]?) -> [String: String] {
        var out = owned ?? [:]
        for (key, value) in server ?? [:] where out[key] == nil {
            out[key] = value
        }
        return out
    }

    private static func warnUnownedSegment(_ segment: String) {
        print("[Compass] \"\(segment)\" is managed server-side and was not added to this device's segments. Use addUserSegment() to assert it from the device.")
    }
}

/// Applies the `MAX_SENT_SEGMENTS` cap to a merged segment list and keeps the
/// `mrf_tooManySegments` user var in step with it. The var is written only on a state
/// transition (over → flagged, fits → unflagged), so the evaluation is cheap enough to
/// run on every beacon.
internal final class SegmentTrimmer {
    private let readOwnedUserVars: () -> [String: String]
    private let setUserVar: (_ name: String, _ value: String) -> Void
    private let removeUserVar: (_ name: String) -> Void

    init(
        readOwnedUserVars: @escaping () -> [String: String],
        setUserVar: @escaping (_ name: String, _ value: String) -> Void,
        removeUserVar: @escaping (_ name: String) -> Void
    ) {
        self.readOwnedUserVars = readOwnedUserVars
        self.setUserVar = setUserVar
        self.removeUserVar = removeUserVar
    }

    func trim(_ segments: [String]) -> [String] {
        let isFlagged = readOwnedUserVars()[MRF_TOO_MANY_SEGMENTS] != nil

        if SegmentOwnership.isOverSegmentLimit(segments) {
            if !isFlagged { setUserVar(MRF_TOO_MANY_SEGMENTS, "true") }
        } else if isFlagged {
            removeUserVar(MRF_TOO_MANY_SEGMENTS)
        }

        return SegmentOwnership.trimSegments(segments)
    }
}
