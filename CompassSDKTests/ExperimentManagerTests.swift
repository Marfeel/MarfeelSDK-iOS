import XCTest
@testable import MarfeelSDK_iOS

class ExperimentManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var manager: ExperimentManager!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ExperimentManagerTests")!
        defaults.removePersistentDomain(forName: "ExperimentManagerTests")
        manager = ExperimentManager(defaults: defaults, userIdProvider: { nil }, siteUserIdProvider: { nil })
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

    func testHandleExperimentGroupsWithSeededRandomIsDeterministic() {
        var callCount = 0
        let seededRandom: () -> Double = {
            callCount += 1
            return 0.25
        }
        let manager1 = ExperimentManager(defaults: defaults, random: seededRandom)
        manager1.handleExperimentGroups(makeExperimentGroups())
        let assignment1 = manager1.getAssignments()["testGroup"]

        manager1.clear()
        let manager2 = ExperimentManager(defaults: defaults, random: seededRandom)
        manager2.handleExperimentGroups(makeExperimentGroups())
        let assignment2 = manager2.getAssignments()["testGroup"]

        XCTAssertEqual(assignment1, assignment2)
    }

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
        let manager = ExperimentManager(
            defaults: defaults,
            random: { XCTFail("random must not be used"); return 0 },
            userIdProvider: { "user-1" },
            siteUserIdProvider: { "site-user" }
        )
        let percentage = DeterministicHash.seededPercentage(userId: "user-1", seed: "A")

        let result = manager.evaluate([
            makeExperience(id: "A", experiment: user(50)),
            makeExperience(id: "A~v1", experiment: user(50)),
        ])

        XCTAssertEqual([percentage <= 50 ? "A" : "A~v1"], result.map { $0.id })
    }

    func testEvaluateFallsBackToSiteUserIdWhenUserIdIsEmpty() {
        let manager = ExperimentManager(
            defaults: defaults,
            random: { XCTFail("random must not be used"); return 0 },
            userIdProvider: { "" },
            siteUserIdProvider: { "site-user" }
        )
        let percentage = DeterministicHash.seededPercentage(userId: "site-user", seed: "A")

        let result = manager.evaluate([
            makeExperience(id: "A", experiment: user(50)),
            makeExperience(id: "A~v1", experiment: user(50)),
        ])

        XCTAssertEqual([percentage <= 50 ? "A" : "A~v1"], result.map { $0.id })
    }

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

    func testHandleAfterClearReassigns() {
        manager.handleExperimentGroups(makeExperimentGroups())
        let first = manager.getAssignments()["testGroup"]
        manager.clear()
        manager.handleExperimentGroups(makeExperimentGroups())
        XCTAssertNotNil(manager.getAssignments()["testGroup"])
        XCTAssertTrue(["variant_a", "variant_b"].contains(first!))
    }

    func testGetTargetingEntriesReturnsAssignments() {
        manager.handleExperimentGroups(makeExperimentGroups())
        let entries = manager.getTargetingEntries()
        XCTAssertNotNil(entries["experiment::testGroup"])
    }
}
