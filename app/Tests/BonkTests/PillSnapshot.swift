import XCTest
import SwiftUI
import AppKit
@testable import Bonk

/// Wegwerp-snapshot: rendert de pill(s) naar een PNG voor de release notes /
/// website. Niet bedoeld als regressietest. Schrijf-pad via env BONK_SHOT_DIR.
@MainActor
final class PillSnapshot: XCTestCase {
    func testRenderPillShot() throws {
        guard let dir = ProcessInfo.processInfo.environment["BONK_SHOT_DIR"] else {
            throw XCTSkip("Zet BONK_SHOT_DIR om de pill-snapshot te genereren.")
        }

        let now = Date()
        let meeting = UpcomingEvent(
            id: "evt-1",
            title: "Designreview met het team",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(60 * 31),
            calendarTitle: "Werk",
            calendarID: "cal-A",
            attendance: .accepted,
            joinURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            location: "Google Meet",
            notes: nil,
            weekday: 2
        )
        let reminder = UpcomingEvent(
            id: "reminder:1",
            title: "Lunchwandeling",
            start: now.addingTimeInterval(60 * 7),
            end: now.addingTimeInterval(60 * 7),
            calendarTitle: "",
            calendarID: "",
            attendance: .none,
            joinURL: nil,
            location: nil,
            notes: nil,
            weekday: 2
        )

        let pill: (UpcomingEvent, Color) -> AnyView = { ev, accent in
            AnyView(PillCardView(
                event: ev, accent: accent, lang: .nl,
                onJoin: {}, onSnooze: { _ in }, onSnoozeUntilStart: {},
                onDismiss: {}, onOpenCalendar: {}
            ))
        }

        let composed = ZStack {
            LinearGradient(
                colors: [Color(hex: "#A78BFA"), Color(hex: "#6366F1"), Color(hex: "#0EA5E9")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                pill(meeting, Color(hex: "#2563EB"))
                pill(reminder, Color(hex: "#7C3AED"))
            }
            .padding(.top, 40)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 820, height: 320)
        .preferredColorScheme(.light)

        let renderer = ImageRenderer(content: composed)
        renderer.scale = 2
        guard let cg = renderer.cgImage else {
            XCTFail("ImageRenderer leverde geen beeld")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: 820, height: 320)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("PNG-encoding mislukt")
            return
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("pill-shot.png")
        try png.write(to: url)
        print("PILL_SHOT_WRITTEN: \(url.path)")
    }
}
