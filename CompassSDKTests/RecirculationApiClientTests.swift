import XCTest
@testable import MarfeelSDK_iOS

class RecirculationApiClientTests: XCTestCase {

    private func links(of payload: [[String: Any]]) -> [[String: Any]] {
        return payload[0]["e"] as! [[String: Any]]
    }

    func testPayloadIncludesNameUrlAndPosition() {
        let payload = RecirculationApiClient.modulesPayload([
            RecirculationModule(name: "mod-1", links: [RecirculationLink(url: "https://a.com", position: 3)])
        ])

        XCTAssertEqual("mod-1", payload[0]["n"] as? String)
        XCTAssertEqual("https://a.com", links(of: payload)[0]["url"] as? String)
        XCTAssertEqual("3", links(of: payload)[0]["p"] as? String)
    }

    func testPayloadOmitsTestVersionWhenAbsent() {
        let payload = RecirculationApiClient.modulesPayload([
            RecirculationModule(name: "mod-1", links: [RecirculationLink(url: "https://a.com", position: 0)])
        ])

        XCTAssertNil(links(of: payload)[0]["tv"])
        XCTAssertNil(links(of: payload)[0]["meta"])
    }

    func testPayloadAddsTestVersionToEveryLink() {
        let payload = RecirculationApiClient.modulesPayload([
            RecirculationModule(
                name: "IL_1",
                links: [
                    RecirculationLink(url: "https://a.com", position: 0),
                    RecirculationLink(url: " ", position: 255),
                ],
                testVersion: "control"
            )
        ])

        for link in links(of: payload) {
            XCTAssertEqual("control", link["tv"] as? String)
            XCTAssertEqual(["tv": "control"], link["meta"] as? [String: String])
        }
    }

    func testPayloadIsSerializable() {
        let payload = RecirculationApiClient.modulesPayload([
            RecirculationModule(
                name: "IL_1",
                links: [RecirculationLink(url: "https://a.com", position: 0)],
                testVersion: "va"
            )
        ])

        XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
    }
}
