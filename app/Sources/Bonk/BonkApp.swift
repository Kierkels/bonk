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
        if app.isPaused {
            // Gepauzeerd: gedimd icoon met een pauze-badge. Zelf naar een (template)
            // NSImage renderen, want een SwiftUI-overlay komt niet betrouwbaar mee in
            // de menubalk (die plat de label tot één afbeelding).
            Image(nsImage: MenuBarLabel.renderPaused(icon: app.menuBarIconName))
        } else if let color = app.menuBarHighlightColor {
            Image(nsImage: MenuBarLabel.renderPill(text: app.menuBarText, icon: app.menuBarIconName, color: color))
                .renderingMode(.original)
        } else if let text = app.menuBarText {
            HStack(spacing: 4) {
                Image(systemName: app.menuBarIconName)
                Text(text)
            }
        } else {
            Image(systemName: app.menuBarIconName)
        }
    }

    /// Rendert icoon + tekst op een gekleurde capsule naar een NSImage met
    /// `isTemplate = false`, zodat de menubalk de echte kleur toont.
    @MainActor
    private static func renderPill(text: String?, icon: String, color: Color) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarPillContent(text: text, icon: icon, color: color))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return NSImage() }
        image.isTemplate = false
        return image
    }

    /// Rendert het gekozen icoon (gedimd) met een pauze-badge naar een template-
    /// NSImage, zodat de menubalk 'm netjes meekleurt in licht/donker.
    @MainActor
    private static func renderPaused(icon: String) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarPausedContent(icon: icon))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return NSImage() }
        image.isTemplate = true
        return image
    }
}

/// Het gepauzeerde menubalk-icoon: het gekozen symbool gedimd met een pauze-badge
/// rechtsonder. Wat extra padding zodat de badge niet wordt afgeknipt.
private struct MenuBarPausedContent: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .regular))
            .opacity(0.45)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(1)
    }
}

/// De gekleurde menubalk-pil: bel (+ tekst) met een contrasterende voorgrond
/// op een capsule in de markeringskleur.
private struct MenuBarPillContent: View {
    let text: String?
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            if let text { Text(text) }
        }
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(color.readableForeground)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color, in: Capsule())
    }
}
