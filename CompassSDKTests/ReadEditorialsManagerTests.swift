import XCTest
@testable import CompassSDK

class ReadEditorialsManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var manager: ReadEditorialsManager!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ReadEditorialsManagerTests")!
        defaults.removePersistentDomain(forName: "ReadEditorialsManagerTests")
        manager = ReadEditorialsManager(defaults: defaults)
    }

    func testAddStoresEditorialId() {
        manager.add("123")
        XCTAssertEqual(["123"], manager.getIds())
    }

    func testAddDeduplicatesButRefreshesOrdering() {
        manager.add("123")
        manager.add("456")
        manager.add("123")
        XCTAssertEqual(["456", "123"], manager.getIds())
    }

    func testAddIgnoresBlankIds() {
        manager.add("")
        manager.add("   ")
        XCTAssertTrue(manager.getIds().isEmpty)
    }

    func testBuildRedParamReturnsEmptyWhenNoIds() {
        XCTAssertEqual("", manager.buildRedParam())
    }

    func testBuildRedParamDeltaEncodesSortedIds() {
        manager.add("130")
        manager.add("120")
        XCTAssertEqual("120,10", manager.buildRedParam())
    }

    func testBuildRedParamSkipsNonNumericIds() {
        manager.add("abc")
        manager.add("100")
        XCTAssertEqual("100", manager.buildRedParam())
    }

    func testClearRemovesStoredIds() {
        manager.add("1")
        manager.clear()
        XCTAssertTrue(manager.getIds().isEmpty)
    }

    func testCapsAt100EntriesFIFO() {
        for i in 0..<105 {
            manager.add(String(1000 + i))
        }
        let ids = manager.getIds()
        XCTAssertEqual(100, ids.count)
        XCTAssertEqual("1005", ids.first)
        XCTAssertEqual("1104", ids.last)
    }
}
