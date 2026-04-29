import Foundation

internal class RecirculationApiClient {
    private let session: URLSession
    private let baseUrl: String

    init(session: URLSession = .shared, baseUrl: String = "https://events.newsroom.bi") {
        self.session = session
        self.baseUrl = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
    }

    func send(eventType: String, modules: [RecirculationModule]) {
        if modules.isEmpty { return }

        guard let url = URL(string: "\(baseUrl)/recirculation/recirculation.php") else { return }

        let tracker = CompassTracker.shared
        let storage = tracker

        let modulesJson: [[String: Any]] = modules.map { module in
            [
                "n": module.name,
                "e": module.links.map { link in
                    ["url": link.url, "p": String(link.position)]
                }
            ]
        }

        guard let modulesData = try? JSONSerialization.data(withJSONObject: modulesJson),
              let modulesString = String(data: modulesData, encoding: .utf8) else { return }

        let now = String(Int64(Date().timeIntervalSince1970))
        let pageUrl = storage.experiencesPageUrl ?? ""

        var body: [String: String] = [
            "t": eventType,
            "n": now,
            "m": modulesString,
            "ac": storage.experiencesAccountId,
            "url": pageUrl,
            "c": pageUrl,
            "ut": String(storage.experiencesUserType),
            "fv": String(storage.experiencesFirstVisitTimestamp),
            "lv": String(storage.experiencesPreviousVisitTimestamp),
            "u": storage.experiencesUserId,
            "s": storage.experiencesSessionId,
            "pageType": String(storage.experiencesPageTechnology),
            "uc": storage.experiencesHasConsent.map { String($0) } ?? "",
            "cc": storage.experiencesConsentCode,
        ]

        if let sui = storage.experiencesRegisteredUserId {
            body["sui"] = sui
        }
        if let lp = storage.experiencesLandingPage {
            body["lp"] = lp
        }

        let bodyString = body.map { "\($0.key)=\(percentEncode($0.value))" }.joined(separator: "&")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)

        session.dataTask(with: request) { _, _, _ in
            // Fire-and-forget
        }.resume()
    }

    private func percentEncode(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
