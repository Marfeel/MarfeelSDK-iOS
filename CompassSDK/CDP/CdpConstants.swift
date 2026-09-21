//
//  CdpConstants.swift
//  CompassSDK
//
//  CDP subsystem constants. Mirrors CdpConstants.kt in the Android SDK.
//

import Foundation

internal let CDP_IDENTITY_RESOLVE_PATH = "/cdp/identity/resolve/"
internal let CDP_IDENTITY_LINK_PATH = "/cdp/identity/link/"
internal let CDP_IDENTITY_DELETE_PATH = "/cdp/identity/delete/"
internal let CDP_IDENTITY_UPDATE_PATH = "/cdp/identity/update/"
internal let CDP_IDENTITY_RESET_PATH = "/cdp/identity/reset/"
internal let CDP_CONSENT_RECORD_PATH = "/cdp/consents/record/"
internal let CDP_CONSENT_CATALOG_PATH = "/cdp/consents/catalog/"
internal let CDP_CONSENT_CHECK_PATH = "/cdp/consents/check/"
internal let CDP_METERS_PATH = "/cdp/meters"

/// Sentinel masterId used before CDP resolves a real one. Segments set pre-identity are
/// written to this bucket and carried over into the real masterId bucket on first
/// identity resolve. Anonymous consent decisions always live under this bucket.
internal let LOCAL_MID_SENTINEL = "local"

/// 180-day TTL for the per-(account, master_id) mirror store. Matches the backend's
/// anonymous-data TTL ("Scylla DefaultAnonymousTTL").
internal let CDP_MIRROR_TTL_MS: Int64 = 180 * 24 * 60 * 60 * 1000

/// Upper bound on the user segments **read back or sent** in a beacon (`useg`). The
/// union is server-first, so device-owned segments are the ones dropped. Storage is
/// never trimmed — only the read-out.
internal let MAX_SENT_SEGMENTS = 100

/// User var set to `true` while the segment union exceeds `MAX_SENT_SEGMENTS`.
internal let MRF_TOO_MANY_SEGMENTS = "mrf_tooManySegments"

/// How long `resetUser()` waits for the best-effort remote tail (the CDP reset POST)
/// before completing anyway. The rotation callers depend on is already done by then.
internal let REMOTE_CLEANUP_TIMEOUT: TimeInterval = 5

/// The "unknown" identity every failed identity/profile call resolves to (fail-open).
internal let UNKNOWN_CDP_IDENTITY = CdpIdentityResponse(masterId: nil, rfv: nil, cohorts: [])

/// CDP uses "personalization" consent. On iOS this maps to the global consent flag,
/// which is permissive unless explicitly set to false.
internal let CDP_MIRROR_SUITE_NAME = "CompassCdpMirror"

/// A master_id is only ever adopted or read back when it is a well-formed UUID.
internal func isValidUuid(_ value: String?) -> Bool {
    guard let value = value else { return false }
    return UUID(uuidString: value) != nil
}
