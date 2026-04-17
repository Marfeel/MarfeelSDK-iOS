import Foundation

internal class ContentResolver {
    private let session: URLSession
    private let queue = DispatchQueue(label: "com.marfeel.contentresolver")
    private var bundleStore: [String: BundleEntry] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(url: String, experienceId: String?, completion: @escaping (String?) -> Void) {
        if let experienceId = experienceId, ContentResolver.isBundledUrl(url) {
            fetchBundledSlice(url: url, experienceId: experienceId, completion: completion)
        } else {
            fetchRaw(url: url, completion: completion)
        }
    }

    // MARK: - Raw fetch

    private func fetchRaw(url: String, completion: @escaping (String?) -> Void) {
        guard let requestUrl = URL(string: url) else {
            completion(nil)
            return
        }
        session.dataTask(with: requestUrl) { data, _, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            completion(String(data: data, encoding: .utf8))
        }.resume()
    }

    // MARK: - Bundled fetch
    //
    // All entry state mutations happen on `queue`. The network call itself runs
    // off-queue; we re-enter `queue` in its completion. Callers arriving while a
    // fetch is in flight are appended to `entry.pending` and drained together
    // when the fetch resolves — no lock is ever held across I/O.

    private func fetchBundledSlice(url: String, experienceId: String, completion: @escaping (String?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { completion(nil); return }
            let entry = self.entryOnQueue(for: url)

            if entry.payload != nil {
                if let slice = self.extractSliceOnQueue(entry: entry, experienceId: experienceId) {
                    completion(slice)
                    return
                }
                self.tryVarsReplayOnQueue(entry: entry, url: url, experienceId: experienceId, completion: completion)
                return
            }

            entry.pending.append((experienceId, completion))
            if entry.isFetching { return }
            entry.isFetching = true

            self.fetchRaw(url: url) { body in
                self.queue.async {
                    entry.isFetching = false
                    if let body = body {
                        entry.payload = self.parseBundle(body)
                    }
                    let pending = entry.pending
                    entry.pending = []
                    for (waiterId, waiterCompletion) in pending {
                        if let slice = self.extractSliceOnQueue(entry: entry, experienceId: waiterId) {
                            waiterCompletion(slice)
                        } else {
                            self.tryVarsReplayOnQueue(entry: entry, url: url, experienceId: waiterId, completion: waiterCompletion)
                        }
                    }
                }
            }
        }
    }

    // Must run on `queue`.
    private func entryOnQueue(for url: String) -> BundleEntry {
        if let existing = bundleStore[url] { return existing }
        let entry = BundleEntry()
        bundleStore[url] = entry
        return entry
    }

    // Must run on `queue`.
    private func extractSliceOnQueue(entry: BundleEntry, experienceId: String) -> String? {
        guard var list = entry.payload?.contents[experienceId], !list.isEmpty else { return nil }
        let slice = list.removeFirst()
        entry.payload?.contents[experienceId] = list
        return slice
    }

    // Must run on `queue`.
    private func tryVarsReplayOnQueue(
        entry: BundleEntry,
        url: String,
        experienceId: String,
        completion: @escaping (String?) -> Void
    ) {
        guard !entry.varsReplayed,
              let vars = entry.payload?.vars, !vars.isEmpty else {
            completion(nil)
            return
        }
        entry.varsReplayed = true
        let replayUrl = ContentResolver.resolveVarsFromUrl(url, vars: vars)

        fetchRaw(url: replayUrl) { body in
            self.queue.async {
                if let body = body, let existing = entry.payload {
                    let retryPayload = self.parseBundle(body)
                    entry.payload = self.mergeBundles(existing: existing, incoming: retryPayload)
                }
                completion(self.extractSliceOnQueue(entry: entry, experienceId: experienceId))
            }
        }
    }

    // MARK: - Bundle parsing

    private func parseBundle(_ body: String) -> BundledPayload {
        guard let data = body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return BundledPayload(contents: [:], vars: [:])
        }

        var vars: [String: String] = [:]
        var contents: [String: [String]] = [:]

        for (key, value) in root {
            if key == "vars", let varsObj = value as? [String: Any] {
                for (vKey, vValue) in varsObj {
                    vars[vKey] = (vValue as? String) ?? "\(vValue)"
                }
                continue
            }
            if let array = value as? [Any] {
                contents[key] = array.map { element in
                    if let str = element as? String { return str }
                    guard let data = try? JSONSerialization.data(withJSONObject: element),
                          let str = String(data: data, encoding: .utf8) else { return "\(element)" }
                    return str
                }
            }
        }

        return BundledPayload(contents: contents, vars: vars)
    }

    private func mergeBundles(existing: BundledPayload, incoming: BundledPayload) -> BundledPayload {
        var mergedContents: [String: [String]] = [:]
        for (key, list) in existing.contents { mergedContents[key] = list }
        for (key, list) in incoming.contents {
            var target = mergedContents[key] ?? []
            for item in list where !target.contains(item) {
                target.append(item)
            }
            mergedContents[key] = target
        }
        let mergedVars = existing.vars.merging(incoming.vars) { _, new in new }
        return BundledPayload(contents: mergedContents, vars: mergedVars)
    }

    // MARK: - Data structures

    internal struct BundledPayload {
        var contents: [String: [String]]
        let vars: [String: String]
    }

    private class BundleEntry {
        var payload: BundledPayload?
        var varsReplayed = false
        var isFetching = false
        var pending: [(String, (String?) -> Void)] = []
    }

    // MARK: - URL analysis

    private static let jukeboxMarker = "flowcards.mrf.io/transformer/"

    static func isBundledUrl(_ url: String) -> Bool {
        guard let idParam = extractIdParam(url) else { return false }
        return idParam.contains(",")
    }

    private static func extractIdParam(_ url: String) -> String? {
        guard let components = URLComponents(string: url) else { return nil }
        if let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
            return id
        }
        if let innerUrl = components.queryItems?.first(where: { $0.name == "url" })?.value,
           let innerComponents = URLComponents(string: innerUrl) {
            return innerComponents.queryItems?.first(where: { $0.name == "id" })?.value
        }
        return nil
    }

    static func resolveVarsFromUrl(_ url: String, vars: [String: String]) -> String {
        if vars.isEmpty { return url }
        let isJukebox = url.contains(jukeboxMarker)
        return isJukebox ? applyVarsToJukeboxInnerUrl(url, vars: vars) : applyVarsToUrl(url, vars: vars)
    }

    private static func applyVarsToUrl(_ url: String, vars: [String: String]) -> String {
        guard var components = URLComponents(string: url) else { return url }
        var items = components.queryItems ?? []
        for (key, value) in vars {
            items.removeAll { $0.name == key }
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items
        return components.string ?? url
    }

    private static func applyVarsToJukeboxInnerUrl(_ url: String, vars: [String: String]) -> String {
        guard var outerComponents = URLComponents(string: url) else { return url }
        guard let innerRaw = outerComponents.queryItems?.first(where: { $0.name == "url" })?.value else { return url }
        let rewrittenInner = applyVarsToUrl(innerRaw, vars: vars)
        var items = outerComponents.queryItems ?? []
        items.removeAll { $0.name == "url" }
        items.append(URLQueryItem(name: "url", value: rewrittenInner))
        outerComponents.queryItems = items
        return outerComponents.string ?? url
    }
}
