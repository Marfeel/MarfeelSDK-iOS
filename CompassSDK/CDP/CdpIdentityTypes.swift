//
//  CdpIdentityTypes.swift
//  CompassSDK
//
//  The well-known identity types for `Cdp.setIdentity` / `Cdp.deleteIdentity`. Mirrors
//  `cdp-core/pkg/identity/identity.go`. The set is **open** — a site can register its
//  own — so this is documentation, never a validation list.
//
//  The first group is **stable**: linking one makes the user registered and their data
//  permanent. The second is **device-bound** and leaves them anonymous, aged out 180
//  days after the last write. Prefer a stable type when your CRM owns the identifier;
//  `isDeterministic: true` forces a device-bound one to registered.
//
//  `email_hash` and `phone_hash` are deliberately absent: the server validates nothing,
//  so they silently create a parallel user that never merges with `*_sha256`. Hash with
//  `Cdp.hashEmail` / `Cdp.hashPhone` and send `emailSha256` / `phoneSha256` instead.
//

import Foundation

public enum CdpIdentityTypes {
    // Stable → registered user, data permanent.
    public static let email = "email"
    public static let emailSha256 = "email_sha256"
    public static let phone = "phone"
    public static let phoneSha256 = "phone_sha256"
    public static let externalId = "external_id"
    public static let customerId = "customer_id"
    public static let registeredUserId = "registered_user_id"

    // Device-bound → anonymous, aged out 180 days after the last write.
    public static let loginId = "login_id"
    public static let crmId = "crm_id"
    public static let cookie = "cookie"
    public static let deviceId = "device_id"
    public static let maid = "maid"
    public static let idfa = "idfa"
    public static let idfv = "idfv"
    public static let rampid = "rampid"
    public static let pushToken = "push_token"

    public static let stable: Set<String> = [
        email, emailSha256, phone, phoneSha256, externalId, customerId, registeredUserId
    ]

    public static let deviceBound: Set<String> = [
        loginId, crmId, cookie, deviceId, maid, idfa, idfv, rampid, pushToken
    ]
}
