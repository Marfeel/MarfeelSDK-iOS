//
//  CdpHash.swift
//  CompassSDK
//
//  Normalisation + SHA-256 for the hashed identity types. The rules match the server
//  (`cdp-core/pkg/identity/normalize.go`) exactly — a divergence here produces a digest
//  the CDP will never match against its own.
//

import Foundation
import CommonCrypto

internal enum CdpHash {
    /// `trim` + lower-case: the server's own rule for emails.
    static func normalizeEmail(_ email: String) -> String {
        return email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Trimmed but **never** case-folded, matching `canonicalPhone`. No further
    /// canonicalisation either: `+34600111222` and `600111222` are two users.
    static func normalizePhone(_ phone: String) -> String {
        return phone.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hashEmail(_ email: String) -> String { sha256Hex(normalizeEmail(email)) }

    static func hashPhone(_ phone: String) -> String { sha256Hex(normalizePhone(phone)) }

    /// 64 lowercase hex chars.
    static func sha256Hex(_ value: String) -> String {
        let bytes = Array(value.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        bytes.withUnsafeBufferPointer { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// The email as a consent subject: `id_type` + `id_value`.
internal struct CdpConsentSubject: Equatable {
    let idType: String
    let idValue: String
}

/// Reduces an email to its consent subject: normalised and reduced to its SHA-256 hex
/// digest under `email_sha256`. Never throws — SHA-256 is always available on iOS, so
/// the plain-`email` fallback of the web SDK is never needed here.
internal func consentEmailIdentity(_ email: String) -> CdpConsentSubject {
    return CdpConsentSubject(idType: CdpIdentityTypes.emailSha256, idValue: CdpHash.hashEmail(email))
}
