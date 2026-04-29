import XCTest
@testable import CompassSDK

class ExperimentManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var manager: ExperimentManager!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ExperimentManagerTests")!
        defaults.removePersistentDomain(forName: "ExperimentManagerTests")
        manager = ExperimentManager(defaults: defaults)
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

    private func makeExperience(id: String, filters: [ExperienceFilter]? = nil) -> Experience {
        return Experience(
            id: id, name: id, type: .inline, family: nil,
            placement: nil, contentUrl: nil, contentType: .unknown,
            features: nil, strategy: nil, selectors: nil, filters: filters, rawJson: [:]
        )
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

    func testFilterByExperimentsKeepsMatchingFilter() {
        manager.handleExperimentGroups(makeExperimentGroups())
        let assignedVariant = manager.getAssignments()["testGroup"]!

        let experience = makeExperience(
            id: "exp1",
            filters: [ExperienceFilter(key: "mrf_exp_testGroup", operator: .equals, values: [assignedVariant])]
        )
        let filtered = manager.filterByExperiments([experience])
        XCTAssertEqual(1, filtered.count)
    }

    func testFilterByExperimentsDropsNonMatchingFilter() {
        manager.handleExperimentGroups(makeExperimentGroups())
        let experience = makeExperience(
            id: "exp1",
            filters: [ExperienceFilter(key: "mrf_exp_testGroup", operator: .equals, values: ["nonexistent"])]
        )
        let filtered = manager.filterByExperiments([experience])
        XCTAssertEqual(0, filtered.count)
    }

    func testFilterByExperimentsKeepsExperienceWithNoFilters() {
        let experience = makeExperience(id: "exp1")
        let filtered = manager.filterByExperiments([experience])
        XCTAssertEqual(1, filtered.count)
    }

    func testFilterByExperimentsKeepsNonExperimentFilters() {
        let experience = makeExperience(
            id: "exp1",
            filters: [ExperienceFilter(key: "url", operator: .equals, values: ["something.com"])]
        )
        let filtered = manager.filterByExperiments([experience])
        XCTAssertEqual(1, filtered.count)
    }

    func testFilterByExperimentsNotEqualsKeepsWhenDiffers() {
        manager.handleExperimentGroups(makeExperimentGroups())
        let assigned = manager.getAssignments()["testGroup"]!
        let other = assigned == "variant_a" ? "variant_b" : "variant_a"

        let experience = makeExperience(
            id: "exp1",
            filters: [ExperienceFilter(key: "mrf_exp_testGroup", operator: .notEquals, values: [other])]
        )
        let filtered = manager.filterByExperiments([experience])
        XCTAssertEqual(1, filtered.count)
    }

    func testFilterByExperimentsNotEqualsDropsWhenMatches() {
        manager.handleExperimentGroups(makeExperimentGroups())
        let assigned = manager.getAssignments()["testGroup"]!

        let experience = makeExperience(
            id: "exp1",
            filters: [ExperienceFilter(key: "mrf_exp_testGroup", operator: .notEquals, values: [assigned])]
        )
        let filtered = manager.filterByExperiments([experience])
        XCTAssertEqual(0, filtered.count)
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
