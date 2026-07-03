//
//  CdpApiClient.swift
//  CompassSDK
//
//  URLSession networking for the CDP. Mirrors CdpApiClient.kt.
//
//  All identity/profile calls are fail-open: any error / non-2xx / unparseable body
//  resolves to UNKNOWN_CDP_IDENTITY rather than surfacing an error. Trailing slashes
//  on the identity paths are part of the contract and must be preserved (so the URLs
//  are built by string concatenation, not appendingPathComponent).
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
        let codeVersion = Bundle.compassSDK?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let deviceType = UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "mobile"
        return "Marfeel-iOS-SDK/\(codeVersion) (\(UIDevice.current.model)) \(deviceType)"
    }

    // MARK: - Identity / profile

    func resolve(_ params: CdpResolveParams, completion: @escaping (CdpIdentityResponse) -> Void) {
        postIdentity(path: CDP_IDENTITY_RESOLVE_PATH, params: params, completion: completion)
    }

    func link(_ params: CdpLinkParams, completion: @escaping (CdpIdentityResponse) -> Void) {
        postIdentity(path: CDP_IDENTITY_LINK_PATH, params: params, completion: completion)
    }

    func update(_ params: CdpProfileUpdateParams, completion: @escaping (CdpIdentityResponse) -> Void) {
        postIdentity(path: CDP_IDENTITY_UPDATE_PATH, params: params, completion: completion)
    }

    private func postIdentity<T: Encodable>(path: String, params: T, completion: @escaping (CdpIdentityResponse) -> Void) {
        guard let url = URL(string: baseString + path), let body = try? JSONEncoder().encode(params) else {
            completion(UNKNOWN_CDP_IDENTITY)
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
                  let parsed = CdpIdentityResponse.decode(from: data) else {
                completion(UNKNOWN_CDP_IDENTITY)
                return
            }
            completion(parsed)
        }.resume()
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
}
