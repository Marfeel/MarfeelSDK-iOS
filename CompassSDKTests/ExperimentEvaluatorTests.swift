import XCTest
@testable import MarfeelSDK_iOS

class ExperimentEvaluatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeExperience(
        id: String,
        name: String? = nil,
        experiment: ExperienceExperiment?,
        placement: String? = nil,
        selector: String? = nil
    ) -> Experience {
        return Experience(
            id: id, name: name ?? id, type: .inline, family: nil,
            placement: placement, contentUrl: nil, contentType: .unknown,
            features: nil, strategy: nil,
            selectors: selector.map { [ExperienceSelector(selector: $0, strategy: "")] },
            filters: nil, rawJson: [:], experiment: experiment
        )
    }

    private func request(_ weight: Double) -> ExperienceExperiment {
        return ExperienceExperiment(type: .request, weight: weight, groupId: nil, variantIds: nil)
    }

    private func user(_ weight: Double) -> ExperienceExperiment {
        return ExperienceExperiment(type: .user, weight: weight, groupId: nil, variantIds: nil)
    }

    private func testGroup(_ groupId: String, _ variantIds: [String]) -> ExperienceExperiment {
        return ExperienceExperiment(type: .testGroup, weight: nil, groupId: groupId, variantIds: variantIds)
    }

    private func evaluator(random: Double) -> ExperimentEvaluator {
        return ExperimentEvaluator(random: { random })
    }

    private func failingRandomEvaluator() -> ExperimentEvaluator {
        return ExperimentEvaluator(random: {
            XCTFail("random must not be used")
            return 0
        })
    }

    private func ids(_ experiences: [Experience]) -> [String] {
        return experiences.map { $0.id }
    }

    // MARK: - Experiences without experiment

    func testExperienceWithoutExperimentIsKeptUntouched() {
        let plain = makeExperience(id: "plain", experiment: nil)
        let result = evaluator(random: 0.5).evaluate([plain], assignments: [:], userId: nil)
        XCTAssertEqual(["plain"], ids(result))
        XCTAssertNil(result[0].experimentation)
    }

    func testTestGroupWithoutGroupIdIsTreatedAsPlainExperience() {
        let experience = makeExperience(
            id: "x",
            experiment: ExperienceExperiment(type: .testGroup, weight: nil, groupId: nil, variantIds: ["a"])
        )
        let result = evaluator(random: 0.5).evaluate([experience], assignments: [:], userId: nil)
        XCTAssertEqual(["x"], ids(result))
        XCTAssertNil(result[0].experimentation)
    }

    // MARK: - Standalone REQUEST

    func testRequestBaseWinsWhenDrawFallsInItsWeight() {
        let base = makeExperience(id: "A", experiment: request(50))
        let variant = makeExperience(id: "A~v1", name: "Variant one", experiment: request(50))

        let result = evaluator(random: 0.3).evaluate([variant, base], assignments: [:], userId: nil)

        XCTAssertEqual(["A"], ids(result))
        XCTAssertEqual(Experimentation(isControl: false, name: "Original"), result[0].experimentation)
    }

    func testRequestVariantWinsAndUsesActionName() {
        let base = makeExperience(id: "A", experiment: request(50))
        let variant = makeExperience(id: "A~v1", name: "Variant one", experiment: request(50))

        let result = evaluator(random: 0.7).evaluate([base, variant], assignments: [:], userId: nil)

        XCTAssertEqual(["A~v1"], ids(result))
        XCTAssertEqual(Experimentation(isControl: false, name: "Variant one"), result[0].experimentation)
    }

    func testRequestDrawEqualToCumulativeWeightWins() {
        let base = makeExperience(id: "A", experiment: request(50))
        let variant = makeExperience(id: "A~v1", experiment: request(50))

        let result = evaluator(random: 0.5).evaluate([base, variant], assignments: [:], userId: nil)

        XCTAssertEqual(["A"], ids(result))
    }

    func testRequestWithoutWinnerMarksBaseAsControl() {
        let base = makeExperience(id: "A", experiment: request(20))
        let variant = makeExperience(id: "A~v1", experiment: request(20))

        let result = evaluator(random: 0.9).evaluate([base, variant], assignments: [:], userId: nil)

        XCTAssertEqual(["A"], ids(result))
        XCTAssertEqual(Experimentation(isControl: true, name: "control"), result[0].experimentation)
    }

    func testRequestWithoutWinnerAndWithoutBaseDropsEveryMember() {
        let v1 = makeExperience(id: "A~v1", experiment: request(10))
        let v2 = makeExperience(id: "A~v2", experiment: request(10))

        let result = evaluator(random: 0.9).evaluate([v1, v2], assignments: [:], userId: nil)

        XCTAssertTrue(result.isEmpty)
    }

    func testLegacySingleRequestWinnerIsOriginal() {
        let single = makeExperience(id: "A", experiment: request(30))
        let result = evaluator(random: 0.1).evaluate([single], assignments: [:], userId: nil)
        XCTAssertEqual(Experimentation(isControl: false, name: "Original"), result[0].experimentation)
    }

    func testLegacySingleRequestLoserIsKeptAsControl() {
        let single = makeExperience(id: "A", experiment: request(30))
        let result = evaluator(random: 0.5).evaluate([single], assignments: [:], userId: nil)
        XCTAssertEqual(["A"], ids(result))
        XCTAssertEqual(Experimentation(isControl: true, name: "control"), result[0].experimentation)
    }

    func testRequestDrawIsSharedAcrossGroups() {
        var calls = 0
        let evaluator = ExperimentEvaluator(random: {
            calls += 1
            return 0.3
        })
        let experiences = [
            makeExperience(id: "A", experiment: request(50)),
            makeExperience(id: "A~v1", experiment: request(50)),
            makeExperience(id: "B", experiment: request(50)),
            makeExperience(id: "B~v1", experiment: request(50)),
        ]

        let result = evaluator.evaluate(experiences, assignments: [:], userId: nil)

        XCTAssertEqual(1, calls)
        XCTAssertEqual(["A", "B"], ids(result))
    }

    // MARK: - Standalone USER

    func testUserExperimentIsDeterministicForTheSameUser() {
        let percentage = DeterministicHash.seededPercentage(userId: "user-1", seed: "A")
        let expectedWinner = percentage <= 50 ? "A" : "A~v1"
        let experiences = [
            makeExperience(id: "A", experiment: user(50)),
            makeExperience(id: "A~v1", experiment: user(50)),
        ]

        let result = failingRandomEvaluator().evaluate(experiences, assignments: [:], userId: "user-1")

        XCTAssertEqual([expectedWinner], ids(result))
        XCTAssertEqual(false, result[0].experimentation?.isControl)
    }

    func testUserExperimentFallsBackToRandomWithoutUserId() {
        let experiences = [
            makeExperience(id: "A", experiment: user(50)),
            makeExperience(id: "A~v1", experiment: user(50)),
        ]

        let result = evaluator(random: 0.9).evaluate(experiences, assignments: [:], userId: nil)

        XCTAssertEqual(["A~v1"], ids(result))
    }

    func testUserExperimentWithEmptyUserIdFallsBackToRandom() {
        let experiences = [
            makeExperience(id: "A", experiment: user(50)),
            makeExperience(id: "A~v1", experiment: user(50)),
        ]

        let result = evaluator(random: 0.1).evaluate(experiences, assignments: [:], userId: "")

        XCTAssertEqual(["A"], ids(result))
    }

    func testRequestAndUserGroupsWithSameBaseIdAreIndependent() {
        let experiences = [
            makeExperience(id: "A", experiment: request(100)),
            makeExperience(id: "A~v1", experiment: user(0)),
        ]

        let result = evaluator(random: 0.5).evaluate(experiences, assignments: [:], userId: nil)

        let byId = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0.experimentation) })
        XCTAssertEqual(Experimentation(isControl: false, name: "Original"), byId["A"])
        XCTAssertEqual(Experimentation(isControl: true, name: "control"), byId["A~v1"])
    }

    // MARK: - Test groups

    func testTestGroupKeepsAssignedVariantAndDropsLoserOnSameSlot() {
        let winner = makeExperience(id: "X", experiment: testGroup("g", ["va"]), selector: "#s1")
        let loser = makeExperience(id: "Y", experiment: testGroup("g", ["vb"]), selector: "#s1")

        let result = evaluator(random: 0.5).evaluate([winner, loser], assignments: ["g": "va"], userId: nil)

        XCTAssertEqual(["X"], ids(result))
        XCTAssertEqual(Experimentation(isControl: false, name: "va"), result[0].experimentation)
    }

    func testTestGroupMarksLoserOnUnclaimedSlotAsControl() {
        let winner = makeExperience(id: "X", experiment: testGroup("g", ["va"]), selector: "#s1")
        let loser = makeExperience(id: "Y", experiment: testGroup("g", ["vb"]), selector: "#s2")

        let result = evaluator(random: 0.5).evaluate([winner, loser], assignments: ["g": "va"], userId: nil)

        XCTAssertEqual(["X", "Y"], ids(result))
        XCTAssertEqual(Experimentation(isControl: true, name: "va"), result[1].experimentation)
    }

    func testTestGroupKeepsOnlyOneControlPerSlotChosenById() {
        let winner = makeExperience(id: "X", experiment: testGroup("g", ["va"]), selector: "#s1")
        let loserZ = makeExperience(id: "Z", experiment: testGroup("g", ["vc"]), selector: "#s2")
        let loserY = makeExperience(id: "Y", experiment: testGroup("g", ["vb"]), selector: "#s2")

        let result = evaluator(random: 0.5).evaluate([winner, loserZ, loserY], assignments: ["g": "va"], userId: nil)

        XCTAssertEqual(["X", "Y"], ids(result))
    }

    func testTestGroupFallsBackToPlacementWhenNoSelectors() {
        let winner = makeExperience(id: "X", experiment: testGroup("g", ["va"]), placement: "top")
        let sameSlot = makeExperience(id: "Y", experiment: testGroup("g", ["vb"]), placement: "top")
        let otherSlot = makeExperience(id: "Z", experiment: testGroup("g", ["vb"]), placement: "bottom")

        let result = evaluator(random: 0.5).evaluate([winner, sameSlot, otherSlot], assignments: ["g": "va"], userId: nil)

        XCTAssertEqual(["X", "Z"], ids(result))
        XCTAssertEqual(true, result[1].experimentation?.isControl)
    }

    func testTestGroupSelectorTakesPrecedenceOverPlacement() {
        let winner = makeExperience(id: "X", experiment: testGroup("g", ["va"]), placement: "top", selector: "#s1")
        let loser = makeExperience(id: "Y", experiment: testGroup("g", ["vb"]), placement: "top", selector: "#s2")

        let result = evaluator(random: 0.5).evaluate([winner, loser], assignments: ["g": "va"], userId: nil)

        XCTAssertEqual(["X", "Y"], ids(result))
    }

    func testTestGroupLoserWithoutSlotIsDropped() {
        let winner = makeExperience(id: "X", experiment: testGroup("g", ["va"]), selector: "#s1")
        let loser = makeExperience(id: "Y", experiment: testGroup("g", ["vb"]))

        let result = evaluator(random: 0.5).evaluate([winner, loser], assignments: ["g": "va"], userId: nil)

        XCTAssertEqual(["X"], ids(result))
    }

    func testTestGroupWithoutAssignmentFailsOpen() {
        let a = makeExperience(id: "X", experiment: testGroup("g", ["va"]), selector: "#s1")
        let b = makeExperience(id: "Y", experiment: testGroup("g", ["vb"]), selector: "#s1")

        let result = evaluator(random: 0.5).evaluate([a, b], assignments: [:], userId: "user-1")

        XCTAssertEqual(["X", "Y"], ids(result))
        XCTAssertNil(result[0].experimentation)
        XCTAssertNil(result[1].experimentation)
    }

    func testTestGroupAssignmentWithoutMembersMarksOneControlPerSlot() {
        let a = makeExperience(id: "X", experiment: testGroup("g", ["va"]), selector: "#s1")
        let b = makeExperience(id: "Y", experiment: testGroup("g", ["vb"]), selector: "#s1")

        let result = evaluator(random: 0.5).evaluate([a, b], assignments: ["g": "control"], userId: nil)

        XCTAssertEqual(["X"], ids(result))
        XCTAssertEqual(Experimentation(isControl: true, name: "control"), result[0].experimentation)
    }

    func testTestGroupMemberInSeveralVariantsWins() {
        let shared = makeExperience(id: "X", experiment: testGroup("g", ["va", "vb"]), selector: "#s1")
        let result = evaluator(random: 0.5).evaluate([shared], assignments: ["g": "vb"], userId: nil)
        XCTAssertEqual(Experimentation(isControl: false, name: "vb"), result[0].experimentation)
    }

    // MARK: - Mixed

    func testKeepsResponseOrderOfKeptExperiences() {
        let experiences = [
            makeExperience(id: "plain-1", experiment: nil),
            makeExperience(id: "A~v1", experiment: request(50)),
            makeExperience(id: "plain-2", experiment: nil),
            makeExperience(id: "A", experiment: request(50)),
        ]

        let result = evaluator(random: 0.9).evaluate(experiences, assignments: [:], userId: nil)

        XCTAssertEqual(["plain-1", "A~v1", "plain-2"], ids(result))
    }

    // MARK: - Helpers parity with web

    func testBaseExperienceId() {
        XCTAssertEqual("A", ExperimentEvaluator.baseExperienceId("A"))
        XCTAssertEqual("A", ExperimentEvaluator.baseExperienceId("A~v1"))
        XCTAssertEqual("A", ExperimentEvaluator.baseExperienceId("A~v1~x"))
        XCTAssertEqual("", ExperimentEvaluator.baseExperienceId("~v1"))
    }

    func testCrc32MatchesStandardCheckValue() {
        XCTAssertEqual(0xCBF4_3926, DeterministicHash.crc32("123456789"))
    }

    func testSeededPercentageMatchesWebSdk() {
        // Value computed with croupier `seededPercentage('9f1c2e-ñ-user', 'IL_abc123')`.
        XCTAssertEqual(
            95.147161395289,
            DeterministicHash.seededPercentage(userId: "9f1c2e-ñ-user", seed: "IL_abc123"),
            accuracy: 1e-9
        )
    }

    // MARK: - DeterministicHash (vectors shared with Croupier `DeterministicHashTest` and web `deterministic.test.ts`)

    func testHashMatchesCroupierLegacyVectors() {
        XCTAssertEqual(3_129_066_013, DeterministicHash.crc32("seed:user"))
        XCTAssertEqual(0.7285424538422376, DeterministicHash.fraction("seed:user"), accuracy: 1e-15)
        XCTAssertEqual(72.85424538422376, DeterministicHash.seededPercentage(userId: "user", seed: "seed"), accuracy: 1e-12)
    }

    func testHashMatchesCroupierMixedVectors() {
        XCTAssertEqual(18_576_395, DeterministicHash.fmix32(DeterministicHash.crc32("seed:user")))
        XCTAssertEqual(0.0043251540046185255, DeterministicHash.fraction("seed:user", hashVersion: 2), accuracy: 1e-15)
        XCTAssertEqual(0.9152210694737732, DeterministicHash.fraction("grüpo:üser-🎯", hashVersion: 2), accuracy: 1e-15)
    }

    func testHashVersionOneAndNilKeepTheLegacyHash() {
        XCTAssertEqual(DeterministicHash.fraction("seed:user"), DeterministicHash.fraction("seed:user", hashVersion: 1))
    }

    func testSelectVariantMatchesWebLegacyVectors() {
        let variants = [WeightedVariant(id: "variant-a", weight: 50), WeightedVariant(id: "variant-b", weight: 50)]

        XCTAssertEqual("variant-a", DeterministicHash.selectVariant(variants, userId: "user-1", seed: "group-a", hashVersion: nil))
        XCTAssertEqual("variant-b", DeterministicHash.selectVariant(variants, userId: "user-2", seed: "group-a", hashVersion: nil))
    }

    func testSelectVariantMixedHashDecouplesEqualLengthSeeds() {
        let uid = "4a4ffef6-8d7e-4484-9fd4-7a3abd4c7bb0"
        let variants = [WeightedVariant(id: "1", weight: 50), WeightedVariant(id: "2", weight: 50)]
        let seedA = "eFmyf219Q3qh6OzYsZOdyw"
        let seedB = "HfdplrMXRIKhGtvBUUZOoQ"

        XCTAssertEqual("2", DeterministicHash.selectVariant(variants, userId: uid, seed: seedA, hashVersion: nil))
        XCTAssertEqual("2", DeterministicHash.selectVariant(variants, userId: uid, seed: seedB, hashVersion: nil))
        XCTAssertEqual("1", DeterministicHash.selectVariant(variants, userId: uid, seed: seedA, hashVersion: 2))
        XCTAssertEqual("2", DeterministicHash.selectVariant(variants, userId: uid, seed: seedB, hashVersion: 2))
    }

    func testSelectVariantReturnsNilWithoutWeightedVariants() {
        XCTAssertNil(DeterministicHash.selectVariant([], userId: "user-1", seed: "group-a", hashVersion: nil))
        XCTAssertNil(DeterministicHash.selectVariant(
            [WeightedVariant(id: "variant-a", weight: 0)], userId: "user-1", seed: "group-a", hashVersion: nil
        ))
    }

    func testSelectVariantSkipsZeroWeightVariants() {
        let variants = [WeightedVariant(id: "off", weight: 0), WeightedVariant(id: "on", weight: 33.3)]

        XCTAssertEqual("on", DeterministicHash.selectVariant(variants, userId: "user-1", seed: "group-a", hashVersion: 2))
    }

    // MARK: - Out of test

    func testOutOfTestGroupDropsEveryMemberAndKeepsNoControl() {
        let a = makeExperience(id: "X", experiment: testGroup("g", ["va"]), selector: "#s1")
        let b = makeExperience(id: "Y", experiment: testGroup("g", ["vb"]), selector: "#s2")

        let result = evaluator(random: 0.5).evaluate([a, b], assignments: [:], userId: nil, outOfTest: ["g"])

        XCTAssertTrue(result.isEmpty)
    }

    func testOutOfTestWinsOverStoredAssignment() {
        let a = makeExperience(id: "X", experiment: testGroup("g", ["va"]), selector: "#s1")

        let result = evaluator(random: 0.5).evaluate([a], assignments: ["g": "va"], userId: nil, outOfTest: ["g"])

        XCTAssertTrue(result.isEmpty)
    }

    func testOutOfTestGroupLeavesOtherGroupsAndPlainExperiencesAlone() {
        let out = makeExperience(id: "X", experiment: testGroup("g", ["va"]), selector: "#s1")
        let assigned = makeExperience(id: "Y", experiment: testGroup("h", ["va"]), selector: "#s1")
        let open = makeExperience(id: "Z", experiment: testGroup("open", ["va"]), selector: "#s1")
        let plain = makeExperience(id: "plain", experiment: nil)

        let result = evaluator(random: 0.5).evaluate(
            [out, assigned, open, plain], assignments: ["h": "va"], userId: nil, outOfTest: ["g"]
        )

        XCTAssertEqual(["Y", "Z", "plain"], ids(result))
        XCTAssertEqual(Experimentation(isControl: false, name: "va"), result[0].experimentation)
        XCTAssertNil(result[1].experimentation)
    }
}
