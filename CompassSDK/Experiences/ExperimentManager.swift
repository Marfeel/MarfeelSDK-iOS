import Foundation

internal class ExperimentManager {
    private static let storageKey = "CompassExperiments"

    private let defaults: UserDefaults
    private let random: () -> Double
    private let evaluator: ExperimentEvaluator
    private let userIdProvider: () -> String?
    private let siteUserIdProvider: () -> String?
    private let queue = DispatchQueue(label: "com.marfeel.experiments", attributes: .concurrent)

    init(
        defaults: UserDefaults = .standard,
        random: @escaping () -> Double = { Double.random(in: 0..<1) },
        userIdProvider: @escaping () -> String? = { CompassTracker.shared.experiencesUserId },
        siteUserIdProvider: @escaping () -> String? = { CompassTracker.shared.experiencesRegisteredUserId }
    ) {
        self.defaults = defaults
        self.random = random
        self.evaluator = ExperimentEvaluator(random: random)
        self.userIdProvider = userIdProvider
        self.siteUserIdProvider = siteUserIdProvider
    }

    func handleExperimentGroups(_ groups: [String: Any]?) {
        guard let groups = groups else { return }
        queue.sync(flags: .barrier) {
            var assignments = loadAssignments()

            for (groupId, groupValue) in groups {
                if assignments[groupId] != nil { continue }
                guard let groupObj = groupValue as? [String: Any],
                      let variants = groupObj["variants"] as? [[String: Any]] else { continue }

                let totalWeight = variants.reduce(0) { $0 + ((($1["weight"] as? Int) ?? 0)) }
                if totalWeight <= 0 { continue }

                let roll = Int(random() * Double(totalWeight))
                var cumulative = 0

                for variant in variants {
                    guard let weight = variant["weight"] as? Int,
                          let variantId = variant["id"] as? String else { continue }
                    cumulative += weight
                    if roll < cumulative {
                        assignments[groupId] = variantId
                        break
                    }
                }
            }

            saveAssignments(assignments)
        }
    }

    /// Applies the web SDK A/B semantics: keeps winners and the control arm (tagged with
    /// `experimentation`), drops the losing variants.
    func evaluate(_ experiences: [Experience]) -> [Experience] {
        let userId = [userIdProvider(), siteUserIdProvider()]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        return evaluator.evaluate(experiences, assignments: getAssignments(), userId: userId)
    }

    func getAssignments() -> [String: String] {
        return queue.sync { loadAssignments() }
    }

    func getTargetingEntries() -> [String: String] {
        var result: [String: String] = [:]
        for (groupId, variantId) in getAssignments() {
            result["experiment::\(groupId)"] = variantId
        }
        return result
    }

    func setAssignment(groupId: String, variantId: String) {
        queue.sync(flags: .barrier) {
            var assignments = loadAssignments()
            assignments[groupId] = variantId
            saveAssignments(assignments)
        }
    }

    func clear() {
        queue.sync(flags: .barrier) {
            defaults.removeObject(forKey: ExperimentManager.storageKey)
        }
    }

    private func loadAssignments() -> [String: String] {
        guard let data = defaults.data(forKey: ExperimentManager.storageKey) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: String]) ?? [:]
    }

    private func saveAssignments(_ assignments: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: assignments) else { return }
        defaults.set(data, forKey: ExperimentManager.storageKey)
    }
}
