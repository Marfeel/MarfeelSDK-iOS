//
//  CdpConstants.swift
//  CompassSDK
//
//  CDP subsystem constants. Mirrors CdpConstants.kt in the Android SDK.
//

import Foundation

internal let CDP_IDENTITY_RESOLVE_PATH = "/cdp/identity/resolve/"
internal let CDP_IDENTITY_LINK_PATH = "/cdp/identity/link/"
internal let CDP_IDENTITY_UPDATE_PATH = "/cdp/identity/update/"
internal let CDP_METERS_PATH = "/cdp/meters"

internal let LOCAL_MID_SENTINEL = "local"

/// 180-day TTL for the per-(account, master_id) mirror store. Matches the backend's
/// anonymous-data TTL ("Scylla DefaultAnonymousTTL").
internal let CDP_MIRROR_TTL_MS: Int64 = 180 * 24 * 60 * 60 * 1000

/// The "unknown" identity every failed identity/profile call resolves to (fail-open).
internal let UNKNOWN_CDP_IDENTITY = CdpIdentityResponse(masterId: nil, rfv: nil, cohorts: [])

/// CDP uses "personalization" consent. On iOS this maps to the global consent flag,
/// which is permissive unless explicitly set to false.
internal let CDP_MIRROR_SUITE_NAME = "CompassCdpMirror"
