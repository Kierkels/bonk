import SwiftUI

@main
struct BonkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(app: appDelegate,
                     store: appDelegate.settingsStore,
                     calendar: appDelegate.calendar)
        } label: {
            MenuBarLabel(app: appDelegate)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: appDelegate.settingsStore,
                         calendar: appDelegate.calendar)
        }
    }
}

/// Aparte view zodat de menubalk-label meeverandert wanneer de AppDelegate
/// publiceert (de label in de App-struct ververst daar niet betrouwbaar op).
private struct MenuBarLabel: View {
    @ObservedObject var app: AppDelegate

    var body: some View {
        if let text = app.menuBarText {
            HStack(spacing: 4) {
                Image(systemName: "bell.fill")
                Text(text)
            }
        } else {
            Image(systemName: "bell.fill")
        }
    }
}
