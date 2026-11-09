import XCTest
@testable import MarfeelSDK_iOS

class WholeModuleAugmenterTests: XCTestCase {
    private var pageUrl: String? = "https://page-1"
    private var augmenter: WholeModuleAugmenter!

    override func setUp() {
        super.setUp()
        pageUrl = "https://page-1"
        augmenter = WholeModuleAugmenter { [weak self] in self?.pageUrl }
    }

    private func module(_ name: String, positions: [Int] = [0]) -> RecirculationModule {
        return RecirculationModule(
            name: name,
            links: positions.map { RecirculationLink(url: "https://\(name)/\($0)", position: $0) }
        )
    }

    func testEligibleFirstTimeAppendsWholeModuleLink() {
        let result = augmenter.onEligible([module("mod-a", positions: [0, 1])])
        XCTAssertEqual(3, result[0].links.count)
        XCTAssertEqual(255, result[0].links.last!.position)
        XCTAssertEqual(" ", result[0].links.last!.url)
    }

    func testEligibleSecondTimeDoesNotReAppend() {
        _ = augmenter.onEligible([module("mod-a")])
        let second = augmenter.onEligible([module("mod-a", positions: [0, 1, 2])])
        XCTAssertFalse(second[0].links.contains { $0.position == 255 })
    }

    func testEligibleAppendsOnlyToModulesNotYetSeen() {
        _ = augmenter.onEligible([module("mod-a")])
        let result = augmenter.onEligible([module("mod-a"), module("mod-b")])
        XCTAssertFalse(result[0].links.contains { $0.position == 255 })
        XCTAssertTrue(result[1].links.contains { $0.position == 255 })
    }

    func testImpressionAfterEligibleAppendsOnce() {
        _ = augmenter.onEligible([module("mod-a")])
        let first = augmenter.onImpression(module("mod-a"))
        let second = augmenter.onImpression(module("mod-a"))

        XCTAssertTrue(first.links.contains { $0.position == 255 })
        XCTAssertFalse(second.links.contains { $0.position == 255 })
    }

    func testImpressionWithoutPriorEligibleDoesNotAppend() {
        let result = augmenter.onImpression(module("mod-orphan"))
        XCTAssertFalse(result.links.contains { $0.position == 255 })
    }

    func testPageUrlChangeResetsModuleState() {
        _ = augmenter.onEligible([module("mod-a")])
        pageUrl = "https://page-2"
        let second = augmenter.onEligible([module("mod-a")])
        XCTAssertTrue(second[0].links.contains { $0.position == 255 })
    }

    func testWholeModuleLinkHasPosition255AndSpaceUrl() {
        let link = WholeModuleAugmenter.wholeModuleLink()
        XCTAssertEqual(255, link.position)
        XCTAssertEqual(" ", link.url)
    }

    func testClientProvidedLinksArePreservedWhenAugmenting() {
        let original = module("mod-a", positions: [0, 1, 42])
        let result = augmenter.onEligible([original])
        XCTAssertEqual(original.links.map { $0.url }, Array(result[0].links.dropLast()).map { $0.url })
    }

    func testEligibleAugmentationPreservesTestVersion() {
        let original = RecirculationModule(
            name: "mod-a",
            links: [RecirculationLink(url: "https://a/0", position: 0)],
            testVersion: "control"
        )
        let result = augmenter.onEligible([original])
        XCTAssertEqual("control", result[0].testVersion)
    }

    func testImpressionAugmentationPreservesTestVersion() {
        _ = augmenter.onEligible([module("mod-a")])
        let original = RecirculationModule(
            name: "mod-a",
            links: [RecirculationLink(url: "https://a/0", position: 0)],
            testVersion: "Original"
        )
        let result = augmenter.onImpression(original)
        XCTAssertTrue(result.links.contains { $0.position == 255 })
        XCTAssertEqual("Original", result.testVersion)
    }
}
