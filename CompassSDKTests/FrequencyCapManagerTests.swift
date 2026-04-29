import XCTest
@testable import CompassSDK

class FrequencyCapManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var now: Int64 = 0
    private var manager: FrequencyCapManager!

    private func millisFor(year: Int, month: Int, day: Int, hour: Int = 12) -> Int64 {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = hour
        let date = cal.date(from: comps)!
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "FrequencyCapManagerTests")!
        defaults.removePersistentDomain(forName: "FrequencyCapManagerTests")
        now = millisFor(year: 2026, month: 4, day: 15)
        manager = FrequencyCapManager(defaults: defaults, clock: { [self] in self.now }, timeZone: TimeZone(identifier: "UTC")!)
        manager.applyResponseConfig([
            "exp1": ["l"], "exp2": ["l"], "keep": ["l"],
            "drop": ["l"], "old": ["l"], "fresh": ["l"],
        ])
    }

    func testTrackImpressionIncrementsLifetimeAndDayCounts() {
        manager.trackImpression(experienceId: "exp1")
        manager.trackImpression(experienceId: "exp1")
        let counts = manager.getCounts(experienceId: "exp1")
        XCTAssertEqual(2, counts["l"])
        XCTAssertEqual(2, counts["d"])
        XCTAssertEqual(2, counts["w"])
        XCTAssertEqual(2, counts["m"])
    }

    func testTrackCloseIncrementsCloseCounts() {
        manager.trackClose(experienceId: "exp1")
        let counts = manager.getCounts(experienceId: "exp1")
        XCTAssertEqual(1, counts["cl"])
        XCTAssertEqual(1, counts["cd"])
        XCTAssertEqual(1, counts["cw"])
        XCTAssertEqual(1, counts["cm"])
    }

    func testLsIsSecondsSinceLastImpression() {
        manager.trackImpression(experienceId: "exp1")
        now += 5_000
        let counts = manager.getCounts(experienceId: "exp1")
        XCTAssertEqual(5, counts["ls"])
    }

    func testClsIsSecondsSinceLastClose() {
        manager.trackClose(experienceId: "exp1")
        now += 42_000
        let counts = manager.getCounts(experienceId: "exp1")
        XCTAssertEqual(42, counts["cls"])
    }

    func testDayCounterResetsOnCalendarDayChange() {
        manager.trackImpression(experienceId: "exp1")
        manager.trackImpression(experienceId: "exp1")
        now = millisFor(year: 2026, month: 4, day: 16)
        manager.trackImpression(experienceId: "exp1")
        let counts = manager.getCounts(experienceId: "exp1")
        XCTAssertEqual(1, counts["d"])
        XCTAssertEqual(3, counts["l"])
    }

    func testWeekCounterSumsAcrossDaysWithinIsoWeek() {
        now = millisFor(year: 2026, month: 4, day: 13) // Monday
        manager.trackImpression(experienceId: "exp1")
        now = millisFor(year: 2026, month: 4, day: 15) // Wednesday
        manager.trackImpression(experienceId: "exp1")
        now = millisFor(year: 2026, month: 4, day: 19) // Sunday
        manager.trackImpression(experienceId: "exp1")
        let counts = manager.getCounts(experienceId: "exp1")
        XCTAssertEqual(3, counts["w"])
    }

    func testWeekCounterRollsOverWhenNewIsoWeekBegins() {
        now = millisFor(year: 2026, month: 4, day: 19) // Sunday
        manager.trackImpression(experienceId: "exp1")
        manager.trackImpression(experienceId: "exp1")
        now = millisFor(year: 2026, month: 4, day: 20) // Monday (new week)
        manager.trackImpression(experienceId: "exp1")
        let counts = manager.getCounts(experienceId: "exp1")
        XCTAssertEqual(1, counts["w"])
        XCTAssertEqual(3, counts["l"])
    }

    func testMonthCounterRollsOverBetweenMonths() {
        manager.trackImpression(experienceId: "exp1")
        manager.trackImpression(experienceId: "exp1")
        now = millisFor(year: 2026, month: 5, day: 1)
        manager.trackImpression(experienceId: "exp1")
        let counts = manager.getCounts(experienceId: "exp1")
        XCTAssertEqual(1, counts["m"])
        XCTAssertEqual(3, counts["l"])
    }

    func testBuildUexpReturnsEmptyWhenNoData() {
        XCTAssertEqual("", manager.buildUexp())
    }

    func testBuildUexpEmitsAllNonZeroCounters() {
        manager.trackImpression(experienceId: "exp1")
        let uexp = manager.buildUexp()
        XCTAssertTrue(uexp.contains("exp1"))
        XCTAssertTrue(uexp.contains("d|1"))
        XCTAssertTrue(uexp.contains("w|1"))
        XCTAssertTrue(uexp.contains("m|1"))
        XCTAssertTrue(uexp.contains("l|1"))
    }

    func testBuildUexpOmitsZeroValuedCounters() {
        manager.trackImpression(experienceId: "exp1")
        let uexp = manager.buildUexp()
        XCTAssertFalse(uexp.contains("cl|"))
        XCTAssertFalse(uexp.contains("cd|"))
        XCTAssertFalse(uexp.contains("cls|"))
    }

    func testBuildUexpEmitsLsOnlyWhenImpressionRecorded() {
        manager.trackClose(experienceId: "exp1")
        let uexp = manager.buildUexp()
        XCTAssertFalse(uexp.contains("ls|"))
        XCTAssertTrue(uexp.contains("cl|") || uexp.contains("cls|"))
    }

    func testBuildUexpIncludesEveryExperienceRegardlessOfRecency() {
        manager.trackImpression(experienceId: "old")
        now += 30 * 24 * 3600 * 1000
        manager.trackImpression(experienceId: "fresh")
        let uexp = manager.buildUexp()
        XCTAssertTrue(uexp.contains("old"))
        XCTAssertTrue(uexp.contains("fresh"))
    }

    func testApplyResponseConfigPrunesExperiencesNotInConfig() {
        manager.trackImpression(experienceId: "keep")
        manager.trackImpression(experienceId: "drop")
        manager.applyResponseConfig(["keep": ["d"]])
        let uexp = manager.buildUexp()
        XCTAssertTrue(uexp.contains("keep"))
        XCTAssertFalse(uexp.contains("drop"))
    }

    func testApplyResponseConfigWithEmptyConfigWipesAll() {
        manager.trackImpression(experienceId: "exp1")
        manager.trackImpression(experienceId: "exp2")
        manager.applyResponseConfig([:])
        XCTAssertEqual("", manager.buildUexp())
    }

    func testApplyResponseConfigPreservesCounterStateForRetained() {
        manager.trackImpression(experienceId: "keep")
        manager.trackImpression(experienceId: "keep")
        manager.trackImpression(experienceId: "drop")
        manager.applyResponseConfig(["keep": ["d"]])
        let counts = manager.getCounts(experienceId: "keep")
        XCTAssertEqual(2, counts["l"])
        XCTAssertEqual(2, counts["d"])
    }

    func testClearWipesAllCounters() {
        manager.trackImpression(experienceId: "exp1")
        manager.clear()
        XCTAssertEqual("", manager.buildUexp())
        XCTAssertEqual(0, manager.getCounts(experienceId: "exp1")["l"])
    }

    func testBuildUexpUsesSemicolonSeparator() {
        manager.trackImpression(experienceId: "exp1")
        manager.trackImpression(experienceId: "exp2")
        let uexp = manager.buildUexp()
        XCTAssertTrue(uexp.contains(";"))
        XCTAssertFalse(uexp.hasPrefix(";"))
        XCTAssertFalse(uexp.hasSuffix(";"))
    }

    func testGetCountsReturnsZerosForUnknownExperience() {
        let counts = manager.getCounts(experienceId: "unknown")
        XCTAssertEqual(0, counts["l"])
        XCTAssertEqual(0, counts["cl"])
        XCTAssertEqual(0, counts["d"])
    }

    func testCountersSurviveSerializationRoundTrip() {
        manager.trackImpression(experienceId: "exp1")
        manager.trackClose(experienceId: "exp1")
        let fresh = FrequencyCapManager(defaults: defaults, clock: { [self] in self.now }, timeZone: TimeZone(identifier: "UTC")!)
        let counts = fresh.getCounts(experienceId: "exp1")
        XCTAssertEqual(1, counts["l"])
        XCTAssertEqual(1, counts["cl"])
        XCTAssertEqual(1, counts["d"])
        XCTAssertEqual(1, counts["cd"])
    }
}
