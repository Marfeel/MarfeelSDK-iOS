import XCTest
@testable import MarfeelSDK_iOS

class ExperimentManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var manager: ExperimentManager!
    private var userVars: [String: String] = [:]
    private var userVarWrites: [(name: String, value: String)] = []

    private let seedA = "eFmyf219Q3qh6OzYsZOdyw"
    private let mixedUid = "4a4ffef6-8d7e-4484-9fd4-7a3abd4c7bb0"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ExperimentManagerTests")!
        defaults.removePersistentDomain(forName: "ExperimentManagerTests")
        userVars = [:]
        userVarWrites = []
        manager = makeManager()
    }

    private func makeManager(
        userId: String? = nil,
        siteUserId: String? = nil,
        random: @escaping () -> Double = { Double.random(in: 0..<1) }
    ) -> ExperimentManager {
        return ExperimentManager(
            defaults: defaults,
            random: random,
            userIdProvider: { userId },
            siteUserIdProvider: { siteUserId },
            readUserVars: { [unowned self] in self.userVars },
            writeUserVar: { [unowned self] name, value in
                self.userVars[name] = value
                self.userVarWrites.append((name, value))
            }
        )
    }

    private func failingRandom() -> () -> Double {
        return { XCTFail("random must not be used"); return 0 }
    }

    private func makeExperimentGroups() -> [String: Any] {
        return [
            "testGroup": [
                "id": "testGroup",
                "name": "Test Group",
                "variants": [
                    ["id": "variant_a", "name": "Variant A", "weight": 50],
                    ["id": "variant_b", "name": "Variant B", "weight": 50],
                ]
            ] as [String: Any]
        ]
    }

    private func makeGroups(
        key: String,
        id: String?,
        hashVersion: Int? = nil,
        variants: [(String, Any)]
    ) -> [String: Any] {
        var group: [String: Any] = [
            "name": key,
            "variants": variants.map { ["id": $0.0, "name": $0.0, "weight": $0.1] as [String: Any] }
        ]
        if let id = id { group["id"] = id }
        if let hashVersion = hashVersion { group["hashVersion"] = hashVersion }
        return [key: group]
    }

    private func hashedTestGroupVariant(_ userId: String) -> String {
        return DeterministicHash.selectVariant(
            [WeightedVariant(id: "variant_a", weight: 50), WeightedVariant(id: "variant_b", weight: 50)],
            userId: userId, seed: "testGroup", hashVersion: nil
        )!
    }

    private func makeExperience(
        id: String,
        experiment: ExperienceExperiment? = nil,
        selector: String? = nil
    ) -> Experience {
        return Experience(
            id: id, name: id, type: .inline, family: nil,
            placement: nil, contentUrl: nil, contentType: .unknown,
            features: nil, strategy: nil,
            selectors: selector.map { [ExperienceSelector(selector: $0, strategy: "")] },
            filters: nil, rawJson: [:], experiment: experiment
        )
    }

    private func testGroup(_ variantId: String) -> ExperienceExperiment {
        return ExperienceExperiment(type: .testGroup, weight: nil, groupId: "testGroup", variantIds: [variantId])
    }

    private func user(_ weight: Double) -> ExperienceExperiment {
        return ExperienceExperiment(type: .user, weight: weight, groupId: nil, variantIds: nil)
    }

    // MARK: - Assignment

    func testHandleExperimentGroupsAssignsVariant() {
        manager.handleExperimentGroups(makeExperimentGroups())
        let assignments = manager.getAssignments()
        XCTAssertNotNil(assignments["testGroup"])
        XCTAssertTrue(["variant_a", "variant_b"].contains(assignments["testGroup"]!))
    }

    func testHandleExperimentGroupsPreservesExistingAssignment() {
        manager.handleExperimentGroups(makeExperimentGroups())
        let first = manager.getAssignments()["testGroup"]
        manager.handleExperimentGroups(makeExperimentGroups())
        let second = manager.getAssignments()["testGroup"]
        XCTAssertEqual(first, second)
    }

    func testHandleExperimentGroupsWithoutUserIdUsesSeededRandom() {
        let seededRandom: () -> Double = { 0.25 }
        let manager1 = makeManager(random: seededRandom)
        manager1.handleExperimentGroups(makeExperimentGroups())
        let assignment1 = manager1.getAssignments()["testGroup"]

        manager1.clear()
        let manager2 = makeManager(random: seededRandom)
        manager2.handleExperimentGroups(makeExperimentGroups())
        let assignment2 = manager2.getAssignments()["testGroup"]

        XCTAssertEqual("variant_a", assignment1)
        XCTAssertEqual(assignment1, assignment2)
    }

    func testHandleExperimentGroupsHashesWithUserId() {
        let manager = makeManager(userId: "user-1", random: failingRandom())

        manager.handleExperimentGroups(makeExperimentGroups())

        XCTAssertEqual(hashedTestGroupVariant("user-1"), manager.getAssignments()["testGroup"])
    }

    func testHandleExperimentGroupsFallsBackToSiteUserIdWhenUserIdIsEmpty() {
        let manager = makeManager(userId: "", siteUserId: "site-user", random: failingRandom())

        manager.handleExperimentGroups(makeExperimentGroups())

        XCTAssertEqual(hashedTestGroupVariant("site-user"), manager.getAssignments()["testGroup"])
    }

    func testHandleExperimentGroupsHonoursHashVersion() {
        let variants: [(String, Any)] = [("1", 50), ("2", 50)]
        let legacy = makeManager(userId: mixedUid, random: failingRandom())
        legacy.handleExperimentGroups(makeGroups(key: "group", id: seedA, variants: variants))
        XCTAssertEqual("2", legacy.getAssignments()["group"])

        legacy.clear()
        let mixed = makeManager(userId: mixedUid, random: failingRandom())
        mixed.handleExperimentGroups(makeGroups(key: "group", id: seedA, hashVersion: 2, variants: variants))
        XCTAssertEqual("1", mixed.getAssignments()["group"])
    }

    func testHandleExperimentGroupsUsesGroupKeyAsSeedWithoutId() {
        let manager = makeManager(userId: mixedUid, random: failingRandom())

        manager.handleExperimentGroups(makeGroups(key: seedA, id: nil, hashVersion: 2, variants: [("1", 50), ("2", 50)]))

        XCTAssertEqual("1", manager.getAssignments()[seedA])
    }

    func testHandleExperimentGroupsAcceptsDecimalWeights() {
        let manager = makeManager(userId: "user-1", random: failingRandom())

        manager.handleExperimentGroups(makeGroups(key: "group", id: "group", variants: [("a", 33.3), ("b", 66.7)]))

        let expected = DeterministicHash.selectVariant(
            [WeightedVariant(id: "a", weight: 33.3), WeightedVariant(id: "b", weight: 66.7)],
            userId: "user-1", seed: "group", hashVersion: nil
        )
        XCTAssertEqual(expected, manager.getAssignments()["group"])
    }

    func testHandleExperimentGroupsKeepsStoredAssignmentOverHash() {
        let manager = makeManager(userId: "user-1", random: failingRandom())
        let notHashed = hashedTestGroupVariant("user-1") == "variant_a" ? "variant_b" : "variant_a"
        manager.setAssignment(groupId: "testGroup", variantId: notHashed)

        manager.handleExperimentGroups(makeExperimentGroups())

        XCTAssertEqual(notHashed, manager.getAssignments()["testGroup"])
    }

    func testHandleExperimentGroupsRehashesWhenStoredVariantIsGone() {
        let manager = makeManager(userId: "user-1", random: failingRandom())
        manager.setAssignment(groupId: "testGroup", variantId: "variant_removed")

        manager.handleExperimentGroups(makeExperimentGroups())

        XCTAssertEqual(hashedTestGroupVariant("user-1"), manager.getAssignments()["testGroup"])
    }

    func testHandleExperimentGroupsRehashesWhenStoredVariantHasNoWeight() {
        let manager = makeManager(userId: "user-1", random: failingRandom())
        manager.setAssignment(groupId: "group", variantId: "paused")

        manager.handleExperimentGroups(makeGroups(key: "group", id: "group", variants: [("paused", 0), ("live", 100)]))

        XCTAssertEqual("live", manager.getAssignments()["group"])
    }

    func testHandleExperimentGroupsDropsGroupsMissingFromResponse() {
        manager.setAssignment(groupId: "finishedGroup", variantId: "v1")

        manager.handleExperimentGroups(makeExperimentGroups())

        let assignments = manager.getAssignments()
        XCTAssertNil(assignments["finishedGroup"])
        XCTAssertNotNil(assignments["testGroup"])
    }

    func testHandleExperimentGroupsWithoutGroupsKeepsAssignments() {
        manager.setAssignment(groupId: "testGroup", variantId: "variant_a")

        manager.handleExperimentGroups(nil)

        XCTAssertEqual(["testGroup": "variant_a"], manager.getAssignments())
    }

    // MARK: - User var

    func testHandleExperimentGroupsWritesAssignmentToUserVar() {
        manager.handleExperimentGroups(makeExperimentGroups())

        XCTAssertEqual(manager.getAssignments()["testGroup"], userVars["mrfExperiment_testGroup"])
    }

    func testHandleExperimentGroupsWritesKeptAssignmentToUserVar() {
        manager.setAssignment(groupId: "testGroup", variantId: "variant_b")
        userVars = [:]

        manager.handleExperimentGroups(makeExperimentGroups())

        XCTAssertEqual("variant_b", userVars["mrfExperiment_testGroup"])
    }

    func testHandleExperimentGroupsDoesNotRewriteUnchangedUserVar() {
        manager.handleExperimentGroups(makeExperimentGroups())
        manager.handleExperimentGroups(makeExperimentGroups())

        XCTAssertEqual(1, userVarWrites.count)
    }

    func testHandleExperimentGroupsOverwritesStaleUserVar() {
        manager.setAssignment(groupId: "testGroup", variantId: "variant_a")
        userVars["mrfExperiment_testGroup"] = "stale"

        manager.handleExperimentGroups(makeExperimentGroups())

        XCTAssertEqual("variant_a", userVars["mrfExperiment_testGroup"])
    }

    func testSetAssignmentWritesUserVar() {
        manager.setAssignment(groupId: "testGroup", variantId: "variant_b")

        XCTAssertEqual("variant_b", userVars["mrfExperiment_testGroup"])
    }

    // MARK: - Evaluation

    func testEvaluateKeepsAssignedVariantAndDropsLoserOnSameSlot() {
        manager.setAssignment(groupId: "testGroup", variantId: "variant_a")
        let experiences = [
            makeExperience(id: "exp_a", experiment: testGroup("variant_a"), selector: "#slot"),
            makeExperience(id: "exp_b", experiment: testGroup("variant_b"), selector: "#slot"),
        ]

        let result = manager.evaluate(experiences)

        XCTAssertEqual(["exp_a"], result.map { $0.id })
        XCTAssertEqual(Experimentation(isControl: false, name: "variant_a"), result[0].experimentation)
    }

    func testEvaluateMarksLoserOnOtherSlotAsControl() {
        manager.setAssignment(groupId: "testGroup", variantId: "variant_a")
        let experiences = [
            makeExperience(id: "exp_a", experiment: testGroup("variant_a"), selector: "#slot-1"),
            makeExperience(id: "exp_b", experiment: testGroup("variant_b"), selector: "#slot-2"),
        ]

        let result = manager.evaluate(experiences)

        XCTAssertEqual(["exp_a", "exp_b"], result.map { $0.id })
        XCTAssertEqual(Experimentation(isControl: true, name: "variant_a"), result[1].experimentation)
    }

    func testEvaluateUsesAssignmentsFromHandleExperimentGroups() {
        manager.handleExperimentGroups(makeExperimentGroups())
        let assigned = manager.getAssignments()["testGroup"]!
        let experiences = [
            makeExperience(id: "exp_a", experiment: testGroup("variant_a"), selector: "#slot"),
            makeExperience(id: "exp_b", experiment: testGroup("variant_b"), selector: "#slot"),
        ]

        let result = manager.evaluate(experiences)

        XCTAssertEqual(1, result.count)
        XCTAssertEqual(assigned, result[0].experimentation?.name)
    }

    func testEvaluateKeepsTestGroupUnmarkedWithoutAssignment() {
        let experiences = [
            makeExperience(id: "exp_a", experiment: testGroup("variant_a"), selector: "#slot"),
            makeExperience(id: "exp_b", experiment: testGroup("variant_b"), selector: "#slot"),
        ]

        let result = manager.evaluate(experiences)

        XCTAssertEqual(2, result.count)
        XCTAssertTrue(result.allSatisfy { $0.experimentation == nil })
    }

    func testEvaluateKeepsExperienceWithoutExperiment() {
        let result = manager.evaluate([makeExperience(id: "exp1")])
        XCTAssertEqual(1, result.count)
        XCTAssertNil(result[0].experimentation)
    }

    func testEvaluateHashesUserExperimentsWithUserId() {
        let manager = makeManager(userId: "user-1", siteUserId: "site-user", random: failingRandom())
        let percentage = DeterministicHash.seededPercentage(userId: "user-1", seed: "A")

        let result = manager.evaluate([
            makeExperience(id: "A", experiment: user(50)),
            makeExperience(id: "A~v1", experiment: user(50)),
        ])

        XCTAssertEqual([percentage <= 50 ? "A" : "A~v1"], result.map { $0.id })
    }

    func testEvaluateFallsBackToSiteUserIdWhenUserIdIsEmpty() {
        let manager = makeManager(userId: "", siteUserId: "site-user", random: failingRandom())
        let percentage = DeterministicHash.seededPercentage(userId: "site-user", seed: "A")

        let result = manager.evaluate([
            makeExperience(id: "A", experiment: user(50)),
            makeExperience(id: "A~v1", experiment: user(50)),
        ])

        XCTAssertEqual([percentage <= 50 ? "A" : "A~v1"], result.map { $0.id })
    }

    // MARK: - Manual assignment and clear

    func testSetAssignmentWritesGivenVariant() {
        manager.setAssignment(groupId: "testGroup", variantId: "variant_b")
        XCTAssertEqual("variant_b", manager.getAssignments()["testGroup"])
    }

    func testSetAssignmentOverridesExisting() {
        manager.handleExperimentGroups(makeExperimentGroups())
        manager.setAssignment(groupId: "testGroup", variantId: "variant_a")
        XCTAssertEqual("variant_a", manager.getAssignments()["testGroup"])
    }

    func testSetAssignmentPreservesOtherGroups() {
        manager.setAssignment(groupId: "groupOne", variantId: "v1")
        manager.setAssignment(groupId: "groupTwo", variantId: "v2")
        let assignments = manager.getAssignments()
        XCTAssertEqual("v1", assignments["groupOne"])
        XCTAssertEqual("v2", assignments["groupTwo"])
    }

    func testClearRemovesAllAssignments() {
        manager.handleExperimentGroups(makeExperimentGroups())
        XCTAssertEqual(1, manager.getAssignments().count)
        manager.clear()
        XCTAssertEqual(0, manager.getAssignments().count)
    }

    func testClearStoredAssignmentsRemovesAssignments() {
        manager.setAssignment(groupId: "testGroup", variantId: "variant_a")

        ExperimentManager.clearStoredAssignments(defaults)

        XCTAssertTrue(manager.getAssignments().isEmpty)
    }

    func testHandleAfterClearReassignsFromNewUserId() {
        manager.setAssignment(groupId: "testGroup", variantId: "variant_a")
        ExperimentManager.clearStoredAssignments(defaults)
        let manager = makeManager(userId: "user-2", random: failingRandom())

        manager.handleExperimentGroups(makeExperimentGroups())

        XCTAssertEqual(hashedTestGroupVariant("user-2"), manager.getAssignments()["testGroup"])
    }

    func testGetTargetingEntriesReturnsAssignments() {
        manager.handleExperimentGroups(makeExperimentGroups())
        let entries = manager.getTargetingEntries()
        XCTAssertNotNil(entries["experiment::testGroup"])
    }
}
