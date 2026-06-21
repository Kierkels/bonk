import XCTest
@testable import Bonk

final class AlertSoundTests: XCTestCase {

    func testChoicesIncludeDefaultSystemAndNone() {
        XCTAssertEqual(AlertSound.allChoices.first, "default")
        XCTAssertEqual(AlertSound.allChoices.last, "none")
        XCTAssertTrue(AlertSound.allChoices.contains("Glass"))
    }

    func testLabels() {
        XCTAssertEqual(AlertSound.label("default", .nl), "Standaard")
        XCTAssertEqual(AlertSound.label("none", .nl), "Geen")
        XCTAssertEqual(AlertSound.label("Glass", .en), "Glass")
    }

    func testNewRuleFieldsDefault() {
        let r = MeetingRule()
        XCTAssertFalse(r.notifyWhenLocked)
        XCTAssertEqual(r.notificationSound, "default")
        XCTAssertFalse(r.repeatSound)
    }
}
