//
//  UserDataMerger.swift
//  CompassSDK
//
//  The read-side views the tracker exposes and the beacon sends: device-owned segments
//  unioned with the Server Segments (server first, deduplicated, trimmed to
//  `MAX_SENT_SEGMENTS` with the `mrf_tooManySegments` flag kept in step) and
//  device-owned vars followed by the Server Properties (device-owned wins).
//
//  When CDP is disabled the server side is empty and the views are the raw stores,
//  still trimmed — the cap is a beacon rule, not a CDP one.
//

import Foundation

internal final class UserDataMerger {
    private let cdpEnabled: () -> Bool
    private let readOwnedSegments: () -> [String]
    private let readOwnedVars: () -> [String: String]
    private let listServerSegments: () -> [String]
    private let getServerSegments: (_ completion: @escaping ([String]) -> Void) -> Void
    private let listServerProperties: () -> [String: String]
    private let getServerProperties: (_ completion: @escaping ([String: String]) -> Void) -> Void
    private let trimmer: SegmentTrimmer

    init(
        cdpEnabled: @escaping () -> Bool,
        readOwnedSegments: @escaping () -> [String],
        readOwnedVars: @escaping () -> [String: String],
        listServerSegments: @escaping () -> [String],
        getServerSegments: @escaping (_ completion: @escaping ([String]) -> Void) -> Void,
        listServerProperties: @escaping () -> [String: String],
        getServerProperties: @escaping (_ completion: @escaping ([String: String]) -> Void) -> Void,
        trimmer: SegmentTrimmer
    ) {
        self.cdpEnabled = cdpEnabled
        self.readOwnedSegments = readOwnedSegments
        self.readOwnedVars = readOwnedVars
        self.listServerSegments = listServerSegments
        self.getServerSegments = getServerSegments
        self.listServerProperties = listServerProperties
        self.getServerProperties = getServerProperties
        self.trimmer = trimmer
    }

    /// Uses whatever Server Segments are known right now.
    func segments() -> [String] {
        let server = cdpEnabled() ? listServerSegments() : []
        return trimmer.trim(SegmentOwnership.mergeSegments(owned: readOwnedSegments(), server: server))
    }

    /// Resolves identity first so the Server Segments are current.
    func segments(completion: @escaping ([String]) -> Void) {
        guard cdpEnabled() else {
            completion(segments())
            return
        }
        getServerSegments { [self] server in
            completion(self.trimmer.trim(SegmentOwnership.mergeSegments(owned: self.readOwnedSegments(), server: server)))
        }
    }

    func vars() -> [String: String] {
        let server = cdpEnabled() ? listServerProperties() : [:]
        return SegmentOwnership.mergeVars(owned: readOwnedVars(), server: server)
    }

    func vars(completion: @escaping ([String: String]) -> Void) {
        guard cdpEnabled() else {
            completion(vars())
            return
        }
        getServerProperties { [self] server in
            completion(SegmentOwnership.mergeVars(owned: self.readOwnedVars(), server: server))
        }
    }
}
