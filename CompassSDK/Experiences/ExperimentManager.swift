import Foundation

internal class ExperimentManager {
    private static let storageKey = "CompassExperiments"
    private static let filterPrefix = "mrf_exp_"

    private let defaults: UserDefaults
    private let random: () -> Double
    private let queue = DispatchQueue(label: "com.marfeel.experiments", attributes: .concurrent)

    init(defaults: UserDefaults = .standard, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.defaults = defaults
        self.random = random
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

    func filterByExperiments(_ experiences: [Experience]) -> [Experience] {
        let assignments = getAssignments()
        return experiences.filter { experience in
            guard let filters = experience.filters else { return true }
            let experimentFilters = filters.filter { $0.key.hasPrefix(ExperimentManager.filterPrefix) }
            if experimentFilters.isEmpty { return true }

            return experimentFilters.allSatisfy { filter in
                let groupId = String(filter.key.dropFirst(ExperimentManager.filterPrefix.count))
                guard let assignedVariant = assignments[groupId] else { return false }
                switch filter.operator {
                case .equals:
                    return filter.values.contains(assignedVariant)
                case .notEquals:
                    return !filter.values.contains(assignedVariant)
                default:
                    return true
                }
            }
        }
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
