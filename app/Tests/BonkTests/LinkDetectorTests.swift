import XCTest
@testable import Bonk

final class LinkDetectorTests: XCTestCase {

    func testDetectsGoogleMeet() {
        let url = LinkDetector.firstURL(in: ["Doe mee: https://meet.google.com/abc-defg-hij"])
        XCTAssertEqual(url?.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testDetectsZoom() {
        let url = LinkDetector.firstURL(in: [nil, "https://us02web.zoom.us/j/123456789?pwd=abc"])
        XCTAssertEqual(url?.host, "us02web.zoom.us")
        XCTAssertEqual(url?.scheme, "https")
    }

    func testDetectsTeams() {
        let url = LinkDetector.firstURL(in: ["https://teams.microsoft.com/l/meetup-join/19%3ameeting_xyz"])
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.host, "teams.microsoft.com")
    }

    func testSearchesMultipleFieldsInOrder() {
        // notes leeg, link in de tweede tekst (bv. location)
        let url = LinkDetector.firstURL(in: ["geen link hier", "kamer + https://meet.google.com/xyz-1234-abc"])
        XCTAssertEqual(url?.absoluteString, "https://meet.google.com/xyz-1234-abc")
    }

    func testTrimsTrailingPunctuation() {
        // link gevolgd door leesteken mag niet meegaan in de URL
        let url = LinkDetector.firstURL(in: ["Link: (https://meet.google.com/abc-defg-hij)."])
        XCTAssertEqual(url?.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testNoLinkReturnsNil() {
        XCTAssertNil(LinkDetector.firstURL(in: ["Geen videogesprek vandaag", nil]))
    }
}
