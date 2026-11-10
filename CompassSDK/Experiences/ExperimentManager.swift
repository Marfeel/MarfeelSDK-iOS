import Foundation

internal class ExperimentManager {
    private static let storageKey = "CompassExperiments"
    static let userVarPrefix = "mrfExperiment_"

    private let defaults: UserDefaults
    private let random: () -> Double
    private let evaluator: ExperimentEvaluator
    private let userIdProvider: () -> String?
    private let siteUserIdProvider: () -> String?
    private let readUserVars: () -> [String: String]
    private let writeUserVar: (_ name: String, _ value: String) -> Void
    private let queue = DispatchQueue(label: "com.marfeel.experiments", attributes: .concurrent)

    init(
        defaults: UserDefaults = .standard,
        random: @escaping () -> Double = { Double.random(in: 0..<1) },
        userIdProvider: @escaping () -> String? = { CompassTracker.shared.experiencesUserId },
        siteUserIdProvider: @escaping () -> String? = { CompassTracker.shared.experiencesRegisteredUserId },
        readUserVars: @escaping () -> [String: String] = { CompassTracker.shared.experiencesUserVars },
        writeUserVar: @escaping (_ name: String, _ value: String) -> Void = { CompassTracker.shared.setUserVar(name: $0, value: $1) }
    ) {
        self.defaults = defaults
        self.random = random
        self.evaluator = ExperimentEvaluator(random: random)
        self.userIdProvider = userIdProvider
        self.siteUserIdProvider = siteUserIdProvider
        self.readUserVars = readUserVars
        self.writeUserVar = writeUserVar
    }

    /// Assigns a variant to every test group in the response, the way the web SDK does
    /// (croupier `experiments/index.ts`): deterministic `seed:userId` hash honouring
    /// `hashVersion`. A stored assignment whose variant is still live is kept, so readers
    /// already in a running test are not reshuffled; groups missing from the response are
    /// dropped. Every assignment is mirrored to the `mrfExperiment_<groupId>` user var so
    /// reports see the arm the reader actually got.
    func handleExperimentGroups(_ groups: [String: Any]?) {
        guard let groups = groups else { return }
        let userId = currentUserId()

        let assignments: [String: String] = queue.sync(flags: .barrier) {
            let stored = loadAssignments()
            var next: [String: String] = [:]

            for (groupId, groupValue) in groups {
                guard let groupObj = groupValue as? [String: Any],
                      let rawVariants = groupObj["variants"] as? [[String: Any]] else { continue }

                let variants = rawVariants.compactMap(ExperimentManager.parseVariant)

                if let kept = stored[groupId], variants.contains(where: { $0.id == kept && $0.weight > 0 }) {
                    next[groupId] = kept
                    continue
                }

                let seed = (groupObj["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? groupId
                let hashVersion = (groupObj["hashVersion"] as? NSNumber)?.intValue

                if let variantId = pickVariant(variants, userId: userId, seed: seed, hashVersion: hashVersion) {
                    next[groupId] = variantId
                }
            }

            saveAssignments(next)
            return next
        }

        syncUserVars(assignments)
    }

    /// Applies the web SDK A/B semantics: keeps winners and the control arm (tagged with
    /// `experimentation`), drops the losing variants.
    func evaluate(_ experiences: [Experience]) -> [Experience] {
        return evaluator.evaluate(experiences, assignments: getAssignments(), userId: currentUserId())
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
        syncUserVars([groupId: variantId])
    }

    func clear() {
        queue.sync(flags: .barrier) {
            ExperimentManager.clearStoredAssignments(defaults)
        }
    }

    /// Used by `resetUser`, which must not instantiate the Experiences stack: the new
    /// user id gets hashed again on the next fetch.
    static func clearStoredAssignments(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    private func currentUserId() -> String? {
        return [userIdProvider(), siteUserIdProvider()]
            .compactMap { $0 }
            .first { !$0.isEmpty }
    }

    private func pickVariant(_ variants: [WeightedVariant], userId: String?, seed: String, hashVersion: Int?) -> String? {
        if let userId = userId,
           let variantId = DeterministicHash.selectVariant(variants, userId: userId, seed: seed, hashVersion: hashVersion) {
            return variantId
        }

        let weighted = variants.filter { $0.weight > 0 }
        let totalWeight = weighted.reduce(0) { $0 + $1.weight }
        guard !weighted.isEmpty, totalWeight > 0 else { return nil }

        let value = random() * totalWeight
        var accumulated = 0.0

        for variant in weighted {
            accumulated += variant.weight
            if value < accumulated { return variant.id }
        }

        return weighted.last?.id
    }

    private static func parseVariant(_ variant: [String: Any]) -> WeightedVariant? {
        guard let id = variant["id"] as? String,
              let weight = (variant["weight"] as? NSNumber)?.doubleValue else { return nil }
        return WeightedVariant(id: id, weight: weight)
    }

    /// Writes only what changed, so a fetch does not re-push the user vars to the CDP.
    private func syncUserVars(_ assignments: [String: String]) {
        guard !assignments.isEmpty else { return }
        let userVars = readUserVars()

        for (groupId, variantId) in assignments {
            let name = "\(ExperimentManager.userVarPrefix)\(groupId)"
            if userVars[name] != variantId {
                writeUserVar(name, variantId)
            }
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
