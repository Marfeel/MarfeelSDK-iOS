//
//  CdpConsentModels.swift
//  CompassSDK
//
//  Publisher consents recorded in the CDP — a privacy policy, a marketing opt-in, a
//  newsletter subscription. Unrelated to the CMP / cookie consent set through
//  `CompassTracking.setConsent`, which gates tracking.
//

import Foundation

public enum CdpConsentStatus: String {
    case accepted
    case rejected

    /// The server answers in its short form (`accept` / `reject`); anything that starts
    /// with `accept` reads as `.accepted`, everything else as `.rejected`.
    internal static func fromWire(_ value: String?) -> CdpConsentStatus {
        guard let value = value, value.hasPrefix("accept") else { return .rejected }
        return .accepted
    }
}

/// Caller-facing shape of a consent decision, see `Cdp.trackConsent`.
public struct CdpConsent {
    public let consentId: String
    /// The version's id from CDP > Settings > Consents. Opaque: sent verbatim.
    public let versionId: String
    public let status: CdpConsentStatus
    public let metadata: [String: String]?
    /// Linked to the master when one exists (as `setIdentity` would); otherwise the
    /// subject of the decision. Hashed on the device before it leaves.
    public let email: String?

    public init(consentId: String, versionId: String, status: CdpConsentStatus, metadata: [String: String]? = nil, email: String? = nil) {
        self.consentId = consentId
        self.versionId = versionId
        self.status = status
        self.metadata = metadata
        self.email = email
    }
}

/// Catalog lookup, see `Cdp.getConsent`.
public struct CdpConsentRef {
    public let consentId: String
    /// Absent → the consent's default version, as configured in Compass.
    public let versionId: String?

    public init(consentId: String, versionId: String? = nil) {
        self.consentId = consentId
        self.versionId = versionId
    }
}

/// Status lookup, see `Cdp.hasConsent`.
public struct CdpConsentQuery {
    public let consentId: String
    /// When given, only an accept at exactly this version counts. Absent → any accepted version.
    public let versionId: String?
    /// Sent alongside the master when both exist, so an email accepted elsewhere answers before it is linked here.
    public let email: String?

    public init(consentId: String, versionId: String? = nil, email: String? = nil) {
        self.consentId = consentId
        self.versionId = versionId
        self.email = email
    }
}

/// How the visitor signals consent. Carried through **verbatim** from the server
/// (`accept_method`), so the value is a plain string; these are the known ones.
public enum CdpConsentAcceptMethod {
    public static let checkBox = "check-box"
    public static let preChecked = "pre-checked"
    /// Show no box at all — submitting the form is the consent.
    public static let formSubmit = "form-submit"
}

/// Whether a visitor who already accepted is prompted again.
public enum CdpConsentShowPolicy: String {
    case always
    case ifNotAccepted = "if-not-accepted"

    /// Only the exact string `if-not-accepted` survives; absent, unknown or wrong-case
    /// folds to `.always` — prompting again is recoverable, suppressing a prompt is not.
    internal static func fromWire(_ value: String?) -> CdpConsentShowPolicy {
        return value == CdpConsentShowPolicy.ifNotAccepted.rawValue ? .ifNotAccepted : .always
    }
}

public struct CdpConsentVersion: Equatable {
    public let versionId: String
    public let label: String
    public let date: String?
    public let displayPrompt: String?
    public let errorMessage: String?
    public let metadata: [String: String]
}

public struct CdpConsentDefinition: Equatable {
    public let consentId: String
    public let name: String
    public let purpose: String?
    public let mandatory: Bool
    /// Render the box accordingly — `CdpConsentAcceptMethod.formSubmit` means show no box at all.
    public let acceptMethod: String
    /// Pair `.ifNotAccepted` with `hasConsent` — this is config, not a verdict.
    public let showPolicy: CdpConsentShowPolicy
    /// nil when the consent has no default version and none was requested.
    public let version: CdpConsentVersion?
}

/// `/cdp/consents/record/` answer.
public struct CdpConsentRecordResponse: Equatable {
    /// The canonical master; may differ from the SDK's after a merge, in which case the
    /// SDK adopts it. Empty or absent for an anonymous decision, which is never adopted.
    public let masterId: String?
    public let consentId: String?
    public let consentVersionId: String?
    /// The server's short vocabulary: `accept` / `reject`. Known mismatch, left as-is.
    public let status: String?
    public let recorded: Bool
    public let stored: Bool

    public init(masterId: String?, consentId: String?, consentVersionId: String?, status: String?, recorded: Bool, stored: Bool) {
        self.masterId = masterId
        self.consentId = consentId
        self.consentVersionId = consentVersionId
        self.status = status
        self.recorded = recorded
        self.stored = stored
    }

    internal static func parse(json root: [String: Any]) -> CdpConsentRecordResponse {
        return CdpConsentRecordResponse(
            masterId: root["master_id"] as? String,
            consentId: root["consent_id"] as? String,
            consentVersionId: cdpString(root["consent_version_id"]),
            status: root["status"] as? String,
            recorded: cdpBool(root["recorded"]) ?? false,
            stored: cdpBool(root["stored"]) ?? false
        )
    }
}

/// The richer status object behind `hasConsent`; deliberately not public.
internal struct CdpConsentCheck: Equatable {
    let masterId: String?
    let consentId: String
    let versionId: String
    let granted: Bool
    let answered: Bool
    var status: CdpConsentStatus? = nil
    var answeredVersionId: String? = nil
}

/// What the SDK remembers about a decision it recorded without a master.
internal struct CdpRememberedConsentDecision: Equatable {
    let versionId: String
    let status: CdpConsentStatus
    let ts: Int64
}

// MARK: - Wire params (internal)

/// `/cdp/consents/record/` body. `master_id` is serialized as an explicit `null` when
/// absent; `metadata` and `timezone` are **omitted** when nil (the replay form sends
/// neither); `idType` / `idValue` are omitted when nil. IP, User-Agent and URL are read
/// server-side and deliberately absent here.
internal struct CdpConsentRecordParams: Equatable {
    let siteId: Int
    let masterId: String?
    let consentId: String
    let consentVersionId: String
    let status: CdpConsentStatus
    var metadata: [String: String]? = nil
    var timezone: String? = nil
    var idType: String? = nil
    var idValue: String? = nil

    func jsonBody() -> [String: Any] {
        var body: [String: Any] = [
            "site_id": siteId,
            "master_id": masterId.map { $0 as Any } ?? NSNull(),
            "consent_id": consentId,
            "consent_version_id": consentVersionId,
            "status": status.rawValue
        ]
        if let metadata = metadata { body["metadata"] = metadata }
        if let timezone = timezone { body["timezone"] = timezone }
        if let idType = idType { body["id_type"] = idType }
        if let idValue = idValue { body["id_value"] = idValue }
        return body
    }
}

/// `/cdp/consents/check/` body — a POST so the subject never travels in a URL.
internal struct CdpConsentCheckParams: Equatable {
    let siteId: Int
    let consentId: String
    var consentVersionId: String? = nil
    var masterId: String? = nil
    var idType: String? = nil
    var idValue: String? = nil

    func jsonBody() -> [String: Any] {
        var body: [String: Any] = ["site_id": siteId, "consent_id": consentId]
        if let consentVersionId = consentVersionId { body["consent_version_id"] = consentVersionId }
        if let masterId = masterId { body["master_id"] = masterId }
        if let idType = idType { body["id_type"] = idType }
        if let idValue = idValue { body["id_value"] = idValue }
        return body
    }
}

internal struct CdpConsentCheckResponse: Equatable {
    let masterId: String?
    let consentId: String
    let consentVersionId: String?
    let granted: Bool
    let answered: Bool
    let status: String?
    let answeredVersionId: String?

    static func parse(json root: [String: Any], fallbackConsentId: String) -> CdpConsentCheckResponse {
        return CdpConsentCheckResponse(
            masterId: root["master_id"] as? String,
            consentId: (root["consent_id"] as? String) ?? fallbackConsentId,
            consentVersionId: cdpString(root["consent_version_id"]),
            granted: cdpBool(root["granted"]) ?? false,
            answered: cdpBool(root["answered"]) ?? false,
            status: root["status"] as? String,
            answeredVersionId: cdpString(root["answered_version_id"])
        )
    }
}

internal struct CdpConsentCatalogVersionItem: Equatable {
    let versionId: String
    let label: String
    let date: String?
    let displayPrompt: String?
    let errorMessage: String?
    let metadata: [String: String]
}

internal struct CdpConsentCatalogItem: Equatable {
    let consentId: String
    let name: String
    let purpose: String?
    let mandatory: Bool
    let acceptMethod: String
    let showPolicy: String?
    let version: CdpConsentCatalogVersionItem?

    static func parse(json raw: [String: Any]) -> CdpConsentCatalogItem? {
        guard let consentId = raw["consent_id"] as? String else { return nil }
        let version = (raw["version"] as? [String: Any]).map { v in
            CdpConsentCatalogVersionItem(
                versionId: cdpString(v["consent_version_id"]) ?? "",
                label: v["label"] as? String ?? "",
                date: v["date"] as? String,
                displayPrompt: v["display_prompt"] as? String,
                errorMessage: v["error_message"] as? String,
                metadata: (v["metadata"] as? [String: Any]).map { cdpStringValues($0) } ?? [:]
            )
        }
        return CdpConsentCatalogItem(
            consentId: consentId,
            name: raw["name"] as? String ?? "",
            purpose: raw["purpose"] as? String,
            mandatory: cdpBool(raw["mandatory"]) ?? false,
            acceptMethod: raw["accept_method"] as? String ?? "",
            showPolicy: raw["show_policy"] as? String,
            version: version
        )
    }
}

/// A string, or the textual form of a JSON number (`7` → `"7"`); nil for null / absent.
internal func cdpString(_ value: Any?) -> String? {
    if let string = value as? String { return string }
    if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
    return nil
}
