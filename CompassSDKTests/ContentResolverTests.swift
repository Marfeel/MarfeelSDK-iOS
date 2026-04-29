import XCTest
@testable import CompassSDK

class ContentResolverTests: XCTestCase {

    func testIsBundledUrlReturnsTrueForCommaInId() {
        XCTAssertTrue(ContentResolver.isBundledUrl("https://example.com/bundle?id=IL_a,IL_b"))
    }

    func testIsBundledUrlReturnsTrueForJukeboxWithCommaInId() {
        let url = "https://flowcards.mrf.io/transformer/x?url=https%3A%2F%2Fexample.com%2Fbundle%3Fid%3DIL_a%2CIL_b"
        XCTAssertTrue(ContentResolver.isBundledUrl(url))
    }

    func testIsBundledUrlReturnsFalseForSingleId() {
        XCTAssertFalse(ContentResolver.isBundledUrl("https://example.com/bundle?id=IL_a"))
    }

    func testIsBundledUrlReturnsFalseForNoIdParam() {
        XCTAssertFalse(ContentResolver.isBundledUrl("https://example.com/bundle?foo=bar"))
    }

    func testResolveVarsAppliesVarsToUrl() {
        let url = "https://example.com/content?id=IL_a,IL_b"
        let result = ContentResolver.resolveVarsFromUrl(url, vars: ["page": "home"])
        XCTAssertTrue(result.contains("page=home"))
        XCTAssertTrue(result.contains("id=IL_a,IL_b"))
    }

    func testResolveVarsAppliesVarsToJukeboxInnerUrl() {
        let innerUrl = "https://example.com/content?id=IL_a,IL_b"
        let encoded = innerUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = "https://flowcards.mrf.io/transformer/x?url=\(encoded)"
        let result = ContentResolver.resolveVarsFromUrl(url, vars: ["page": "home"])
        // Vars should be applied to inner URL, not outer
        XCTAssertTrue(result.contains("flowcards.mrf.io/transformer/"))
        // The inner url param should now contain page=home
        XCTAssertTrue(result.contains("page"))
    }

    func testResolveVarsReturnsOriginalWhenEmptyVars() {
        let url = "https://example.com/content?id=IL_a"
        let result = ContentResolver.resolveVarsFromUrl(url, vars: [:])
        XCTAssertEqual(url, result)
    }
}
