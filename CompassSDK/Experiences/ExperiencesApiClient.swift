import Foundation

internal class ExperiencesApiClient {
    private let session: URLSession
    private let experimentManager: ExperimentManager
    private let frequencyCapManager: FrequencyCapManager
    private let readEditorialsManager: ReadEditorialsManager
    private let baseUrl: String
    private let networkInfoProvider: NetworkInfoProviding

    init(
        session: URLSession = .shared,
        experimentManager: ExperimentManager,
        frequencyCapManager: FrequencyCapManager,
        readEditorialsManager: ReadEditorialsManager,
        baseUrl: String = "https://flowcards.mrf.io",
        networkInfoProvider: NetworkInfoProviding = NetworkInfoProvider()
    ) {
        self.session = session
        self.experimentManager = experimentManager
        self.frequencyCapManager = frequencyCapManager
        self.readEditorialsManager = readEditorialsManager
        self.baseUrl = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        self.networkInfoProvider = networkInfoProvider
    }

    func fetch(url pageUrl: String, customTargeting: [String: String], completion: @escaping ([String: Any]?) -> Void) {
        guard let requestUrl = buildUrl(pageUrl: pageUrl, customTargeting: customTargeting) else {
            completion(nil)
            return
        }

        session.dataTask(with: requestUrl) { data, _, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            completion(json)
        }.resume()
    }

    private func buildUrl(pageUrl: String, customTargeting: [String: String]) -> URL? {
        let tracker = CompassTracker.shared

        guard var components = URLComponents(string: "\(baseUrl)/json/experiences/app") else { return nil }
        var items: [URLQueryItem] = []

        items.append(URLQueryItem(name: "sid", value: tracker.experiencesAccountId))
        items.append(URLQueryItem(name: "ptch", value: String(tracker.experiencesPageTechnology)))
        items.append(URLQueryItem(name: "url", value: pageUrl))
        items.append(URLQueryItem(name: "canonical_url", value: pageUrl))
        items.append(URLQueryItem(name: "seid", value: tracker.experiencesSessionId))
        items.append(URLQueryItem(name: "uid", value: tracker.experiencesUserId))

        if let suid = tracker.experiencesRegisteredUserId {
            items.append(URLQueryItem(name: "suid", value: suid))
        }

        items.append(URLQueryItem(name: "utyp", value: String(tracker.experiencesUserType)))
        items.append(URLQueryItem(name: "fvst", value: String(tracker.experiencesFirstVisitTimestamp)))

        let segments = tracker.experiencesUserSegments
        if !segments.isEmpty {
            items.append(URLQueryItem(name: "useg", value: segments.joined(separator: ",")))
        }

        if let ref = tracker.experiencesPreviousPageUrl {
            items.append(URLQueryItem(name: "ref", value: ref))
        }

        if let kbps = networkInfoProvider.getConnectionSpeedKbps() {
            items.append(URLQueryItem(name: "kbps", value: String(kbps)))
        }
        if let ctyp = networkInfoProvider.getConnectionType() {
            items.append(URLQueryItem(name: "ctyp", value: ctyp))
        }

        let uexp = frequencyCapManager.buildUexp()
        if !uexp.isEmpty {
            items.append(URLQueryItem(name: "uexp", value: uexp))
        }

        let red = readEditorialsManager.buildRedParam()
        if !red.isEmpty {
            items.append(URLQueryItem(name: "red", value: red))
        }

        items.append(URLQueryItem(name: "v", value: "2"))

        let trg = buildTargetingParam(customTargeting: customTargeting, tracker: tracker)
        if !trg.isEmpty {
            items.append(URLQueryItem(name: "trg", value: trg))
        }

        components.queryItems = items
        return components.url
    }

    private func buildTargetingParam(customTargeting: [String: String], tracker: CompassTracker) -> String {
        var parts: [String] = []

        for (key, value) in tracker.experiencesUserVars {
            parts.append("userVar::\(key)=\(value)")
        }
        for (key, value) in tracker.experiencesSessionVars {
            parts.append("sessionVar::\(key)=\(value)")
        }
        for (key, value) in tracker.experiencesPageVars {
            parts.append("pageVar::\(key)=\(value)")
        }
        for (key, value) in experimentManager.getTargetingEntries() {
            parts.append("\(key)=\(value)")
        }
        for (key, value) in customTargeting {
            parts.append("\(key)=\(value)")
        }

        return parts.joined(separator: "&")
    }
}
