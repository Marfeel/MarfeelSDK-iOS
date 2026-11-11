import Foundation

/// Port of the web SDK experiment evaluation (croupier `experiments/evaluate/shared.ts` + `inline.ts`).
/// Decides, for every experience carrying an `experiment`, whether it is the winner, the control
/// or must be dropped, and tags kept ones with `experimentation` (isControl / name).
internal final class ExperimentEvaluator {
    static let variantSeparator: Character = "~"
    private static let controlName = "control"
    private static let originalName = "Original"

    private struct Group {
        let type: ExperimentType
        let groupKey: String
        var members: [Experience]
    }

    private struct Outcome {
        let winners: Set<ObjectIdentifier>
        let variantId: String?
        let failOpen: Bool
        var outOfTest = false

        static let open = Outcome(winners: [], variantId: nil, failOpen: true)
        static let out = Outcome(winners: [], variantId: nil, failOpen: false, outOfTest: true)
    }

    private struct Evaluation {
        let type: ExperimentType
        let groupKey: String
        let groupSize: Int
        let isWinner: Bool
        let name: String
        let outOfTest: Bool
    }

    private let random: () -> Double

    /// - Parameter random: returns a value in `0..<1`.
    init(random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.random = random
    }

    static func baseExperienceId(_ id: String) -> String {
        return id.split(separator: variantSeparator, maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? id
    }

    /// - Parameter outOfTest: test groups the reader is not part of: none of their members is
    ///   served or tagged. Unlike a group without assignment, which fails open.
    func evaluate(
        _ experiences: [Experience],
        assignments: [String: String],
        userId: String?,
        outOfTest: Set<String> = []
    ) -> [Experience] {
        let evaluations = evaluateExperiences(experiences, assignments: assignments, userId: userId, outOfTest: outOfTest)
        let controlIds = testGroupControlIds(experiences, evaluations)
            .union(standaloneControlIds(experiences, evaluations))

        return experiences.compactMap { experience in
            guard let evaluation = evaluations[ObjectIdentifier(experience)] else { return experience }

            if evaluation.outOfTest { return nil }

            if evaluation.isWinner {
                experience.experimentation = Experimentation(isControl: false, name: evaluation.name)
                return experience
            }

            let isLegacySingle = evaluation.type != .testGroup && evaluation.groupSize == 1
            if isLegacySingle || controlIds.contains(ObjectIdentifier(experience)) {
                experience.experimentation = Experimentation(isControl: true, name: evaluation.name)
                return experience
            }

            return nil
        }
    }

    // MARK: - Evaluation

    private func evaluateExperiences(
        _ experiences: [Experience],
        assignments: [String: String],
        userId: String?,
        outOfTest: Set<String>
    ) -> [ObjectIdentifier: Evaluation] {
        // One draw per evaluation shared by every REQUEST group, taken only when needed.
        var requestDraw: Double?
        let request: () -> Double = { [unowned self] in
            if let draw = requestDraw { return draw }
            let draw = self.randomPercentage()
            requestDraw = draw
            return draw
        }
        var evaluations: [ObjectIdentifier: Evaluation] = [:]

        for group in groupExperiences(experiences) {
            let outcome = pickOutcome(group, assignments: assignments, userId: userId, outOfTest: outOfTest, request: request)
            if outcome.failOpen { continue }

            for member in group.members {
                let isWinner = outcome.winners.contains(ObjectIdentifier(member))
                evaluations[ObjectIdentifier(member)] = Evaluation(
                    type: group.type,
                    groupKey: group.groupKey,
                    groupSize: group.members.count,
                    isWinner: isWinner,
                    name: resolveName(member, group: group, isWinner: isWinner, variantId: outcome.variantId),
                    outOfTest: outcome.outOfTest
                )
            }
        }

        return evaluations
    }

    private func groupExperiences(_ experiences: [Experience]) -> [Group] {
        var order: [String] = []
        var groups: [String: Group] = [:]

        for experience in experiences {
            guard let experiment = experience.experiment else { continue }

            let groupKey: String
            if experiment.type == .testGroup {
                guard let groupId = experiment.groupId else { continue }
                groupKey = groupId
            } else {
                groupKey = ExperimentEvaluator.baseExperienceId(experience.id)
            }

            let compositeKey = "\(experiment.type.rawValue):\(groupKey)"
            if groups[compositeKey] != nil {
                groups[compositeKey]?.members.append(experience)
            } else {
                order.append(compositeKey)
                groups[compositeKey] = Group(type: experiment.type, groupKey: groupKey, members: [experience])
            }
        }

        return order.compactMap { groups[$0] }
    }

    private func pickOutcome(
        _ group: Group,
        assignments: [String: String],
        userId: String?,
        outOfTest: Set<String>,
        request: () -> Double
    ) -> Outcome {
        switch group.type {
        case .testGroup:
            return pickTestGroupOutcome(group, assignments: assignments, outOfTest: outOfTest)
        case .request:
            return pickStandaloneOutcome(group, randomValue: request())
        case .user:
            return pickStandaloneOutcome(group, randomValue: userRandom(group, userId: userId))
        }
    }

    private func pickTestGroupOutcome(_ group: Group, assignments: [String: String], outOfTest: Set<String>) -> Outcome {
        if outOfTest.contains(group.groupKey) { return .out }

        guard let variantId = assignments[group.groupKey] else { return .open }

        let winners = group.members
            .filter { $0.experiment?.variantIds?.contains(variantId) ?? false }
            .map(ObjectIdentifier.init)

        return Outcome(winners: Set(winners), variantId: variantId, failOpen: false)
    }

    private func pickStandaloneOutcome(_ group: Group, randomValue: Double) -> Outcome {
        var cumulative = 0.0

        for member in group.members.sorted(by: ExperimentEvaluator.byId) {
            cumulative += member.experiment?.weight ?? 0
            if randomValue <= cumulative {
                return Outcome(winners: [ObjectIdentifier(member)], variantId: nil, failOpen: false)
            }
        }

        return Outcome(winners: [], variantId: nil, failOpen: false)
    }

    private func userRandom(_ group: Group, userId: String?) -> Double {
        guard let userId = userId, !userId.isEmpty else { return randomPercentage() }
        return DeterministicHash.seededPercentage(userId: userId, seed: group.groupKey)
    }

    private func randomPercentage() -> Double {
        return (random() * 100).rounded(.down)
    }

    private func resolveName(_ member: Experience, group: Group, isWinner: Bool, variantId: String?) -> String {
        if group.type == .testGroup {
            return variantId ?? ""
        }
        if !isWinner {
            return ExperimentEvaluator.controlName
        }
        return member.id.contains(ExperimentEvaluator.variantSeparator) ? member.name : ExperimentEvaluator.originalName
    }

    // MARK: - Control selection

    /// Native experiences may not carry selectors, so the placement is used as the slot fallback.
    private static func slot(_ experience: Experience) -> String? {
        return experience.selectors?.first?.selector ?? experience.placement
    }

    /// JS string ordering (UTF-16 code units), used by the web SDK.
    private static func byId(_ a: Experience, _ b: Experience) -> Bool {
        return a.id.utf16.lexicographicallyPrecedes(b.id.utf16)
    }

    private func testGroupControlIds(
        _ experiences: [Experience],
        _ evaluations: [ObjectIdentifier: Evaluation]
    ) -> Set<ObjectIdentifier> {
        var winnerSlotsByGroup: [String: Set<String>] = [:]
        var nonWinnersByGroup: [String: [Experience]] = [:]

        // Sorted by id because iOS loses the response order when parsing JSON objects.
        for experience in experiences.sorted(by: ExperimentEvaluator.byId) {
            guard let evaluation = evaluations[ObjectIdentifier(experience)],
                  evaluation.type == .testGroup else { continue }

            if evaluation.isWinner {
                if let slot = ExperimentEvaluator.slot(experience) {
                    winnerSlotsByGroup[evaluation.groupKey, default: []].insert(slot)
                }
            } else {
                nonWinnersByGroup[evaluation.groupKey, default: []].append(experience)
            }
        }

        var controlIds = Set<ObjectIdentifier>()

        for (groupKey, nonWinners) in nonWinnersByGroup {
            let winnerSlots = winnerSlotsByGroup[groupKey] ?? []
            var seenSlots = Set<String>()

            for experience in nonWinners {
                guard let slot = ExperimentEvaluator.slot(experience),
                      !winnerSlots.contains(slot),
                      !seenSlots.contains(slot) else { continue }
                seenSlots.insert(slot)
                controlIds.insert(ObjectIdentifier(experience))
            }
        }

        return controlIds
    }

    private func standaloneControlIds(
        _ experiences: [Experience],
        _ evaluations: [ObjectIdentifier: Evaluation]
    ) -> Set<ObjectIdentifier> {
        var nonWinnersByGroup: [String: [Experience]] = [:]
        var winningGroups = Set<String>()

        for experience in experiences {
            guard let evaluation = evaluations[ObjectIdentifier(experience)],
                  evaluation.type != .testGroup,
                  evaluation.groupSize > 1 else { continue }

            let groupKey = "\(evaluation.type.rawValue):\(evaluation.groupKey)"
            if evaluation.isWinner {
                winningGroups.insert(groupKey)
            } else {
                nonWinnersByGroup[groupKey, default: []].append(experience)
            }
        }

        var controlIds = Set<ObjectIdentifier>()

        for (groupKey, nonWinners) in nonWinnersByGroup where !winningGroups.contains(groupKey) {
            if let base = nonWinners.first(where: { $0.id == ExperimentEvaluator.baseExperienceId($0.id) }) {
                controlIds.insert(ObjectIdentifier(base))
            }
        }

        return controlIds
    }
}

internal struct WeightedVariant {
    let id: String
    let weight: Double
}

/// Must stay in lockstep with the web SDK `deterministic.ts` and Croupier `DeterministicHash`,
/// which CompassMiddleware also recomputes (`experimentFallback.ts`) for readers without a stored
/// `mrfExperiment_<groupId>` user var.
internal enum DeterministicHash {
    static let mixedHashVersion = 2
    private static let unsignedIntRange = 4_294_967_296.0

    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
        }
        return value
    }

    static func crc32(_ key: String) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in key.utf8 {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    static func fmix32(_ hash: UInt32) -> UInt32 {
        var mixed = hash
        mixed ^= mixed >> 16
        mixed = mixed &* 0x85EB_CA6B
        mixed ^= mixed >> 13
        mixed = mixed &* 0xC2B2_AE35
        mixed ^= mixed >> 16
        return mixed
    }

    /// `[0, 1)` value of `key`: plain CRC32 for hash version 1 (or none), CRC32 + `fmix32` from 2.
    static func fraction(_ key: String, hashVersion: Int? = nil) -> Double {
        let crc = crc32(key)
        let hash = (hashVersion ?? 1) >= mixedHashVersion ? fmix32(crc) : crc
        return Double(hash) / unsignedIntRange
    }

    /// Standalone USER experiments: always hash version 1, as the web SDK does.
    static func seededPercentage(userId: String, seed: String) -> Double {
        return fraction("\(seed):\(userId)") * 100
    }

    /// Test-group variant for `userId`, the same pick as web `selectVariant` and the
    /// CompassMiddleware fallback. Nil when no variant has a positive weight.
    static func selectVariant(_ variants: [WeightedVariant], userId: String, seed: String, hashVersion: Int?) -> String? {
        let weighted = variants.filter { $0.weight > 0 }
        let totalWeight = weighted.reduce(0) { $0 + $1.weight }
        guard !weighted.isEmpty, totalWeight > 0 else { return nil }

        let value = fraction("\(seed):\(userId)", hashVersion: hashVersion) * totalWeight
        var accumulated = 0.0

        for variant in weighted {
            accumulated += variant.weight
            if value < accumulated { return variant.id }
        }

        return weighted.last?.id
    }
}
