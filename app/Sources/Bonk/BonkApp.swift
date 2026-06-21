import SwiftUI
import AppKit

@main
struct BonkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(app: appDelegate,
                     store: appDelegate.settingsStore,
                     calendar: appDelegate.calendar,
                     updates: appDelegate.updateChecker)
        } label: {
            MenuBarLabel(app: appDelegate)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: appDelegate.settingsStore,
                         calendar: appDelegate.calendar,
                         updates: appDelegate.updateChecker)
        }
    }
}

/// Aparte view zodat de menubalk-label meeverandert wanneer de AppDelegate
/// publiceert (de label in de App-struct ververst daar niet betrouwbaar op).
private struct MenuBarLabel: View {
    @ObservedObject var app: AppDelegate

    var body: some View {
        // Bij een markering renderen we het label zélf naar een gekleurde
        // (niet-template) afbeelding. MenuBarExtra maakt het label anders
        // monochroom (template), waardoor de gekleurde achtergrond wegvalt.
        if let color = app.menuBarHighlightColor {
            Image(nsImage: MenuBarLabel.renderPill(text: app.menuBarText, color: color))
                .renderingMode(.original)
        } else if let text = app.menuBarText {
            HStack(spacing: 4) {
                Image(systemName: "bell.fill")
                Text(text)
            }
        } else {
            Image(systemName: "bell.fill")
        }
    }

    /// Rendert bel + tekst op een gekleurde capsule naar een NSImage met
    /// `isTemplate = false`, zodat de menubalk de echte kleur toont.
    @MainActor
    private static func renderPill(text: String?, color: Color) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarPillContent(text: text, color: color))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return NSImage() }
        image.isTemplate = false
        return image
    }
}

/// De gekleurde menubalk-pil: bel (+ tekst) met een contrasterende voorgrond
/// op een capsule in de markeringskleur.
private struct MenuBarPillContent: View {
    let text: String?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bell.fill")
            if let text { Text(text) }
        }
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(color.readableForeground)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color, in: Capsule())
    }
}
