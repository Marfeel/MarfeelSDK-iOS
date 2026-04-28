import XCTest
@testable import CompassSDK

class ExperiencesResponseParserTests: XCTestCase {
    private let parser = ExperiencesResponseParser()

    private func loadJson(_ name: String) -> [String: Any] {
        // Try bundle resource first, then fall back to file path
        if let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        // Fallback: load from known path relative to project
        let path = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Failed to load \(name).json")
            return [:]
        }
        return json
    }

    func testParsesSmallResponseIntoFlatList() {
        let result = parser.parse(loadJson("experiences_response_small"))
        XCTAssertFalse(result.experiences.isEmpty)
    }

    func testParsesInlineActionsWithCorrectType() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let inlines = result.experiences.filter { $0.type == .inline }
        XCTAssertFalse(inlines.isEmpty)
        XCTAssertEqual(.inline, inlines.first!.type)
    }

    func testParsesExperienceIdAndName() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let cta = result.experiences.first { $0.name.contains("home-cta-widget") }
        XCTAssertNotNil(cta)
        XCTAssertEqual("IL_mLTwLgXbRS-MJzh1rJM6ng", cta!.id)
    }

    func testParsesTextHTMLContentTypeAndUrl() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let cta = result.experiences.first { $0.id == "IL_mLTwLgXbRS-MJzh1rJM6ng" }
        XCTAssertNotNil(cta)
        XCTAssertEqual(.textHTML, cta!.contentType)
        XCTAssertTrue(cta!.contentUrl!.contains("example.com"))
    }

    func testParsesJsonContentType() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let recommender = result.experiences.first { $0.id == "IL_r1-HQ0psRiiLuHZTpi9lDQ" }
        XCTAssertNotNil(recommender)
        XCTAssertEqual(.json, recommender!.contentType)
    }

    func testParsesCompassActionsWithoutContentUrl() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let compass = result.experiences.filter { $0.type == .compass }
        XCTAssertFalse(compass.isEmpty)
        XCTAssertNil(compass.first!.contentUrl)
    }

    func testParsesAdManagerActions() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let ads = result.experiences.filter { $0.type == .adManager }
        XCTAssertEqual(2, ads.count)
    }

    func testParsesAffiliationEnhancerActions() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let affiliation = result.experiences.filter { $0.type == .affiliationEnhancer }
        XCTAssertEqual(1, affiliation.count)
    }

    func testSkipsTargetingAndContentMetadataKeys() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let targeting = result.experiences.filter { $0.type.rawValue == "targeting" }
        let content = result.experiences.filter { $0.type.rawValue == "content" }
        XCTAssertTrue(targeting.isEmpty)
        XCTAssertTrue(content.isEmpty)
    }

    func testExtractsFrequencyCapFromTargeting() {
        let result = parser.parse(loadJson("experiences_response_small"))
        XCTAssertFalse(result.frequencyCapConfig.isEmpty)
        XCTAssertNotNil(result.frequencyCapConfig["IL_HMNmL7lWTOWBldjNWm1PgQ"])
    }

    func testParsesSelectors() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let cta = result.experiences.first { $0.id == "IL_mLTwLgXbRS-MJzh1rJM6ng" }
        let selectors = cta!.selectors
        XCTAssertNotNil(selectors)
        XCTAssertEqual("#slot-a", selectors!.first!.selector)
        XCTAssertEqual("replace", selectors!.first!.strategy)
    }

    func testParsesFeatures() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let cta = result.experiences.first { $0.id == "IL_mLTwLgXbRS-MJzh1rJM6ng" }
        XCTAssertEqual("contextual", cta!.features?["mode"] as? String)
        XCTAssertEqual(true, cta!.features?["removable"] as? Bool)
    }

    func testParsesStrategy() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let cta = result.experiences.first { $0.id == "IL_mLTwLgXbRS-MJzh1rJM6ng" }
        XCTAssertEqual("replace", cta!.strategy)
    }

    func testHandlesFlowcardsCardsKey() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let flowcards = result.experiences.filter { $0.type == .flowcards }
        XCTAssertEqual(0, flowcards.count)
    }

    func testParsesLargeResponseWithMultipleInlineExperiences() {
        let result = parser.parse(loadJson("experiences_response_large"))
        let inlines = result.experiences.filter { $0.type == .inline }
        XCTAssertTrue(inlines.count >= 10)
    }

    func testParsesFamilyWhenPresent() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let recommender = result.experiences.first { $0.id == "IL_r1-HQ0psRiiLuHZTpi9lDQ" }
        XCTAssertEqual(.recommender, recommender!.family)
    }

    func testFamilyIsNilWhenAbsent() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let cta = result.experiences.first { $0.id == "IL_mLTwLgXbRS-MJzh1rJM6ng" }
        XCTAssertNil(cta!.family)
    }

    func testUnknownFamilyMapsToUnknown() {
        let json: [String: Any] = [
            "inline": [
                "actions": [
                    "test": [
                        "id": "test1",
                        "family": "somefuturefamily"
                    ]
                ]
            ]
        ]
        let result = parser.parse(json)
        XCTAssertEqual(.unknown, result.experiences.first!.family)
    }

    func testPreservesRawJson() {
        let result = parser.parse(loadJson("experiences_response_small"))
        let compass = result.experiences.first { $0.type == .compass }
        XCTAssertNotNil(compass)
        XCTAssertNotNil(compass!.rawJson["recirculationModules"])
    }

    func testExtractsEditorialId() {
        let result = parser.parse(loadJson("experiences_response_small"))
        XCTAssertEqual("190281109", result.editorialId)
    }

    func testTreeFilterGroupWithEmptyChildrenProducesNoFilters() {
        let json: [String: Any] = [
            "compass": [
                "actions": [
                    "a": [
                        "id": "AC_1",
                        "filters": [
                            "type": "group",
                            "children": [Any](),
                            "logic": "AND"
                        ]
                    ]
                ]
            ]
        ]
        let result = parser.parse(json)
        XCTAssertNil(result.experiences.first!.filters)
    }

    func testTreeFilterTopLevelConditionMapsComparatorToOperator() {
        let json: [String: Any] = [
            "experimentation": [
                "actions": [
                    "a": [
                        "id": "AC_1",
                        "filters": [
                            "type": "condition",
                            "field": "url",
                            "comparator": "eq",
                            "values": ["https://dev.marfeel.co/"]
                        ]
                    ]
                ]
            ]
        ]
        let result = parser.parse(json)
        let filters = result.experiences.first!.filters!
        XCTAssertEqual(1, filters.count)
        XCTAssertEqual("url", filters[0].key)
        XCTAssertEqual(.equals, filters[0].operator)
        XCTAssertEqual(["https://dev.marfeel.co/"], filters[0].values)
    }

    func testTreeFilterGroupFlattensNestedConditionChildren() {
        let json: [String: Any] = [
            "compass": [
                "actions": [
                    "a": [
                        "id": "AC_1",
                        "filters": [
                            "type": "group",
                            "logic": "AND",
                            "children": [
                                ["type": "condition", "field": "url", "comparator": "contains", "values": ["news"]],
                                ["type": "condition", "field": "lang", "comparator": "neq", "values": ["es"]]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let result = parser.parse(json)
        let filters = result.experiences.first!.filters!
        XCTAssertEqual(2, filters.count)
        XCTAssertEqual(.like, filters[0].operator)
        XCTAssertEqual(.notEquals, filters[1].operator)
    }

    func testLegacyArrayFilterFormStillParses() {
        let json: [String: Any] = [
            "inline": [
                "actions": [
                    "a": [
                        "id": "IL_1",
                        "filters": [
                            ["key": "url", "operator": "EQUALS", "values": ["https://example.com"]]
                        ]
                    ]
                ]
            ]
        ]
        let result = parser.parse(json)
        let filters = result.experiences.first!.filters!
        XCTAssertEqual(1, filters.count)
        XCTAssertEqual("url", filters[0].key)
        XCTAssertEqual(.equals, filters[0].operator)
    }
}
