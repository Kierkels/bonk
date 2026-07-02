import XCTest
@testable import Bonk

final class AppSettingsTests: XCTestCase {

    // MARK: Ingeklapte menu-secties (persistentie)

    func testDecodesLegacySettingsWithoutCollapsedSections() throws {
        // Oude opslag zonder `menuCollapsedSections` → default: niets ingeklapt.
        let data = try JSONEncoder().encode(AppSettings.default)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "menuCollapsedSections")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertTrue(decoded.menuCollapsedSections.isEmpty)
    }

    func testCollapsedSectionsRoundTrip() throws {
        var s = AppSettings.default
        s.menuCollapsedSections = ["later", "skipped"]
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.menuCollapsedSections, ["later", "skipped"])
    }
}
