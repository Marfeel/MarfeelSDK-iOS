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
    private let removeUserVar: (_ name: String) -> Void
    private let queue = DispatchQueue(label: "com.marfeel.experiments", attributes: .concurrent)

    /// User-var groups the reader is out of, as of the last response.
    private var outOfTestGroups: Set<String> = []

    init(
        defaults: UserDefaults = .standard,
        random: @escaping () -> Double = { Double.random(in: 0..<1) },
        userIdProvider: @escaping () -> String? = { CompassTracker.shared.experiencesUserId },
        siteUserIdProvider: @escaping () -> String? = { CompassTracker.shared.experiencesRegisteredUserId },
        readUserVars: @escaping () -> [String: String] = { CompassTracker.shared.experiencesUserVars },
        writeUserVar: @escaping (_ name: String, _ value: String) -> Void = { CompassTracker.shared.setUserVar(name: $0, value: $1) },
        removeUserVar: @escaping (_ name: String) -> Void = { CompassTracker.shared.removeUserVar(name: $0) }
    ) {
        self.defaults = defaults
        self.random = random
        self.evaluator = ExperimentEvaluator(random: random)
        self.userIdProvider = userIdProvider
        self.siteUserIdProvider = siteUserIdProvider
        self.readUserVars = readUserVars
        self.writeUserVar = writeUserVar
        self.removeUserVar = removeUserVar
    }

    /// Assigns a variant to every test group in the response, the way the web SDK does
    /// (croupier `experiments/index.ts`): deterministic `seed:userId` hash honouring
    /// `hashVersion`. A stored assignment whose variant is still live is kept, so readers
    /// already in a running test are not reshuffled; groups missing from the response are
    /// dropped. Every assignment is mirrored to the `mrfExperiment_<groupId>` user var so
    /// reports see the arm the reader actually got.
    ///
    /// A group with `source: USER_VAR` takes its variant from the user var the client sets,
    /// read on every fetch so the reader follows its current value (no hash, no weights,
    /// no kept assignment). A missing or unmapped value without a fallback variant takes the
    /// reader out of the test: no assignment, no user var, nothing served from the group.
    func handleExperimentGroups(_ groups: [String: Any]?) {
        guard let groups = groups else { return }
        let userId = currentUserId()
        let userVars = readUserVars()

        let (assignments, outOfTest): ([String: String], Set<String>) = queue.sync(flags: .barrier) {
            let stored = loadAssignments()
            var next: [String: String] = [:]
            var dropped: Set<String> = []

            for (groupId, groupValue) in groups {
                guard let groupObj = groupValue as? [String: Any],
                      let rawVariants = groupObj["variants"] as? [[String: Any]] else { continue }

                if UserVarGroup.isUserVar(groupObj) {
                    if let variantId = UserVarGroup.resolveVariant(groupObj, userVars: userVars) {
                        next[groupId] = variantId
                    } else {
                        dropped.insert(groupId)
                    }
                    continue
                }

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
            outOfTestGroups = dropped
            return (next, dropped)
        }

        syncUserVars(assignments, userVars: userVars, outOfTest: outOfTest)
    }

    /// Applies the web SDK A/B semantics: keeps winners and the control arm (tagged with
    /// `experimentation`), drops the losing variants.
    func evaluate(_ experiences: [Experience]) -> [Experience] {
        let (assignments, outOfTest) = queue.sync { (loadAssignments(), outOfTestGroups) }

        return evaluator.evaluate(experiences, assignments: assignments, userId: currentUserId(), outOfTest: outOfTest)
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
            outOfTestGroups.remove(groupId)
        }
        syncUserVars([groupId: variantId], userVars: readUserVars())
    }

    func clear() {
        queue.sync(flags: .barrier) {
            ExperimentManager.clearStoredAssignments(defaults)
            outOfTestGroups = []
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
    /// A reader who drops out of a user-var group loses the variant recorded earlier.
    private func syncUserVars(_ assignments: [String: String], userVars: [String: String], outOfTest: Set<String> = []) {
        for (groupId, variantId) in assignments {
            let name = "\(ExperimentManager.userVarPrefix)\(groupId)"
            if userVars[name] != variantId {
                writeUserVar(name, variantId)
            }
        }

        for groupId in outOfTest {
            let name = "\(ExperimentManager.userVarPrefix)\(groupId)"
            if userVars[name] != nil {
                removeUserVar(name)
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

/// A test group whose variant comes from a user var the client sets, instead of our hash
/// (web SDK: croupier `experiments/userVar.ts`). The only reader of the `source`,
/// `userVarKey`, `userVarMapping` and `fallbackVariantId` fields of a group.
internal enum UserVarGroup {
    private static let sourceUserVar = "USER_VAR"

    static func isUserVar(_ group: [String: Any]) -> Bool {
        return group["source"] as? String == sourceUserVar
    }

    /// The variant mapped to the current value of the user var, else the fallback variant.
    /// Values are compared exactly. Nil when the reader is out of the test: no value, an
    /// unmapped value without fallback, or a variant that is not in the group.
    static func resolveVariant(_ group: [String: Any], userVars: [String: String]) -> String? {
        let value = (group["userVarKey"] as? String).flatMap { userVars[$0] }
        let mapping = group["userVarMapping"] as? [[String: Any]] ?? []
        let mapped = value.flatMap { current in
            mapping.first { $0["value"] as? String == current }?["variantId"] as? String
        }

        guard let variantId = mapped ?? group["fallbackVariantId"] as? String else { return nil }

        let variants = group["variants"] as? [[String: Any]] ?? []
        return variants.contains { $0["id"] as? String == variantId } ? variantId : nil
    }
}
