//
//  CdpConsentMemoryStore.swift
//  CompassSDK
//
//  The SDK's own memory of consent decisions it recorded **without** a master_id:
//  `/cdp/consents/check/` cannot look those up, so `Cdp.hasConsent` answers from here
//  until the replay re-records them under a master. Always under the
//  `LOCAL_MID_SENTINEL` bucket, per account. Cleared as a whole by a user reset.
//

import Foundation

internal class CdpConsentMemoryStore {
    private let store: CdpMirrorStore<[String: CdpRememberedConsentDecision]>

    init(defaults: UserDefaults, clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        store = CdpMirrorStore<[String: CdpRememberedConsentDecision]>(
            defaults: defaults,
            prefix: "cdpconsents_",
            payloadKey: "decisions",
            serialize: { decisions in
                decisions.mapValues { decision -> [String: Any] in
                    ["versionId": decision.versionId, "status": decision.status.rawValue, "ts": NSNumber(value: decision.ts)]
                }
            },
            deserialize: { payload in
                guard let raw = payload as? [String: Any] else { return [:] }
                var out: [String: CdpRememberedConsentDecision] = [:]
                for (consentId, value) in raw {
                    guard let entry = value as? [String: Any], let versionId = entry["versionId"] as? String else { continue }
                    out[consentId] = CdpRememberedConsentDecision(
                        versionId: versionId,
                        status: CdpConsentStatus.fromWire(entry["status"] as? String),
                        ts: (entry["ts"] as? NSNumber)?.int64Value ?? 0
                    )
                }
                return out
            },
            defaultValue: [:],
            clock: clock
        )
    }

    /// A fresh copy each time; empty on a miss.
    func getRemembered(account: String?) -> [String: CdpRememberedConsentDecision] {
        return store.read(account: account, masterId: LOCAL_MID_SENTINEL)
    }

    /// A newer decision on the same consent replaces the older one.
    func remember(account: String?, consentId: String, decision: CdpRememberedConsentDecision) {
        var current = getRemembered(account: account)
        current[consentId] = decision
        store.write(account: account, masterId: LOCAL_MID_SENTINEL, value: current)
    }

    /// Drops only the named decisions; forgetting the last one clears the bucket; unknown ids write nothing.
    func forget(account: String?, consentIds: [String]) {
        let current = getRemembered(account: account)
        let remaining = current.filter { !consentIds.contains($0.key) }
        if remaining.count == current.count { return }

        if remaining.isEmpty {
            store.clear(account: account, masterId: LOCAL_MID_SENTINEL)
        } else {
            store.write(account: account, masterId: LOCAL_MID_SENTINEL, value: remaining)
        }
    }

    func clear(account: String?) { store.clear(account: account, masterId: LOCAL_MID_SENTINEL) }
}
