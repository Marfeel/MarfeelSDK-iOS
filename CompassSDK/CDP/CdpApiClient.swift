//
//  CdpApiClient.swift
//  CompassSDK
//
//  URLSession networking for the CDP. Mirrors CdpApiClient.kt.
//
//  Rule of thumb for failure values: calls whose response feeds the Cached Identity on
//  success but must not poison it on failure (delete, reset, consents) complete with
//  `nil`; resolve / link / update complete with the `UNKNOWN_CDP_IDENTITY` shape.
//  Nothing here ever throws. Trailing slashes on the identity paths are part of the
//  contract and must be preserved (so the URLs are built by string concatenation, not
//  appendingPathComponent). Methods are overridable so tests can stub the transport.
//

import Foundation
import UIKit

internal struct IncrementResult {
    let status: Int
    let state: MeterState?
}

internal class CdpApiClient {
    private let session: URLSession
    private let baseUrl: URL?

    init(session: URLSession = .shared, baseUrl: URL? = TrackingConfig.shared.endpoint) {
        self.session = session
        self.baseUrl = baseUrl
    }

    private var baseString: String {
        guard let string = baseUrl?.absoluteString else { return "" }
        return string.hasSuffix("/") ? String(string.dropLast()) : string
    }

    private var userAgent: String {
        let deviceType = UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "mobile"
        return "Marfeel-iOS-SDK/\(SDK_VERSION) (\(UIDevice.current.model)) \(deviceType)"
    }

    // MARK: - Identity / profile

    func resolve(_ params: CdpResolveParams, completion: @escaping (CdpIdentityResponse) -> Void) {
        postIdentity(path: CDP_IDENTITY_RESOLVE_PATH, body: try? JSONEncoder().encode(params), completion: completion)
    }

    func link(_ params: CdpLinkParams, completion: @escaping (CdpIdentityResponse) -> Void) {
        postIdentity(path: CDP_IDENTITY_LINK_PATH, body: try? JSONEncoder().encode(params), completion: completion)
    }

    func update(_ params: CdpProfileUpdateParams, completion: @escaping (CdpIdentityResponse) -> Void) {
        postIdentity(path: CDP_IDENTITY_UPDATE_PATH, body: try? JSONEncoder().encode(params), completion: completion)
    }

    /// Nil on any failure — never `UNKNOWN_CDP_IDENTITY`, which would poison the cache.
    func delete(_ params: CdpDeleteParams, completion: @escaping (CdpDeleteResponse?) -> Void) {
        postJson(path: CDP_IDENTITY_DELETE_PATH, body: try? JSONEncoder().encode(params)) { root in
            guard let root = root else { completion(nil); return }
            completion(CdpDeleteResponse(identity: CdpIdentityResponse.parse(json: root), deleted: cdpInt(root["deleted"]) ?? 0))
        }
    }

    /// Expires the site's server-held tracking cookies. On native there are no such
    /// cookies to present, so this is parity plumbing — the server answers `cleared: []`.
    /// Body is `{ site_id }` and nothing else. Nil on failure; never throws.
    func reset(siteId: Int, completion: @escaping (CdpResetResponse?) -> Void) {
        postJson(path: CDP_IDENTITY_RESET_PATH, body: try? JSONSerialization.data(withJSONObject: ["site_id": siteId])) { root in
            guard let root = root else { completion(nil); return }
            completion(CdpResetResponse(
                reset: cdpBool(root["reset"]) ?? false,
                siteId: cdpInt(root["site_id"]),
                cleared: (root["cleared"] as? [Any])?.compactMap { $0 as? String } ?? []
            ))
        }
    }

    private func postIdentity(path: String, body: Data?, completion: @escaping (CdpIdentityResponse) -> Void) {
        postJson(path: path, body: body) { root in
            completion(root.map { CdpIdentityResponse.parse(json: $0) } ?? UNKNOWN_CDP_IDENTITY)
        }
    }

    // MARK: - Consents

    /// `master_id` goes out as an explicit `null` when absent; `metadata` / `timezone` /
    /// `id_type` / `id_value` are omitted when nil. Nil on failure; never throws.
    func recordConsent(_ params: CdpConsentRecordParams, completion: @escaping (CdpConsentRecordResponse?) -> Void) {
        postJson(path: CDP_CONSENT_RECORD_PATH, body: try? JSONSerialization.data(withJSONObject: params.jsonBody())) { root in
            completion(root.map { CdpConsentRecordResponse.parse(json: $0) })
        }
    }

    /// GET catalog: `?site_id=&consent_id=&consent_version_id?=`. Completes with the items
    /// (0 or 1; empty when the requested version is unknown), or nil on failure.
    func fetchConsentCatalog(siteId: Int, consentId: String, versionId: String?, completion: @escaping ([CdpConsentCatalogItem]?) -> Void) {
        guard var components = URLComponents(string: baseString + CDP_CONSENT_CATALOG_PATH) else {
            completion(nil)
            return
        }
        var items = [
            URLQueryItem(name: "site_id", value: String(siteId)),
            URLQueryItem(name: "consent_id", value: consentId)
        ]
        if let versionId = versionId { items.append(URLQueryItem(name: "consent_version_id", value: versionId)) }
        components.queryItems = items
        guard let url = components.url else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data = data,
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                completion(nil)
                return
            }
            guard let consents = root["consents"] as? [Any] else {
                completion([])
                return
            }
            completion(consents.compactMap { ($0 as? [String: Any]).flatMap { CdpConsentCatalogItem.parse(json: $0) } })
        }.resume()
    }

    /// A POST, unlike the catalog: the subject (master or email) stays out of URLs and logs.
    func fetchConsentStatus(_ params: CdpConsentCheckParams, completion: @escaping (CdpConsentCheckResponse?) -> Void) {
        postJson(path: CDP_CONSENT_CHECK_PATH, body: try? JSONSerialization.data(withJSONObject: params.jsonBody())) { root in
            completion(root.map { CdpConsentCheckResponse.parse(json: $0, fallbackConsentId: params.consentId) })
        }
    }

    // MARK: - Meters

    func fetchMeters(siteId: String, masterId: String, completion: @escaping ([MeterState]?) -> Void) {
        guard var components = URLComponents(string: baseString + CDP_METERS_PATH) else {
            completion(nil)
            return
        }
        components.queryItems = [
            URLQueryItem(name: "site_id", value: siteId),
            URLQueryItem(name: "master_id", value: masterId)
        ]
        guard let url = components.url else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data = data else {
                // Fail-open: SWR keeps the last-good mirror.
                completion(nil)
                return
            }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let meters = root["meters"] as? [[String: Any]] else {
                // Non-object / non-array meters → treat as empty list, not an error.
                completion([])
                return
            }
            completion(meters.map { MeterState.from(json: $0) })
        }.resume()
    }

    func incrementMeter(name: String, siteId: String, masterId: String, completion: @escaping (IncrementResult) -> Void) {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard var components = URLComponents(string: baseString + CDP_METERS_PATH + "/\(encodedName)/increment") else {
            completion(IncrementResult(status: 0, state: nil))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "site_id", value: siteId),
            URLQueryItem(name: "master_id", value: masterId)
        ]
        guard let url = components.url else {
            completion(IncrementResult(status: 0, state: nil))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, response, error in
            if error != nil {
                completion(IncrementResult(status: 0, state: nil))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(IncrementResult(status: 0, state: nil))
                return
            }
            // A 404 must reach the caller so it can surface MeterNotFoundError.
            guard (200..<300).contains(http.statusCode), let data = data else {
                completion(IncrementResult(status: http.statusCode, state: nil))
                return
            }
            let state = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { $0 }.map { MeterState.from(json: $0) }
            completion(IncrementResult(status: http.statusCode, state: state))
        }.resume()
    }

    // MARK: - Transport

    /// POST a JSON body; the parsed object on 2xx, nil on transport error, non-2xx, a
    /// non-object body or an unencodable request.
    private func postJson(path: String, body: Data?, completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: baseString + path), let body = body else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data = data,
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                completion(nil)
                return
            }
            completion(root)
        }.resume()
    }
}
