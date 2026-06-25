import SwiftUI
import AppKit

/// Een knop die een toetscombinatie opneemt. Tijdens opnemen vangt een lokale
/// `NSEvent`-monitor de volgende toetsaanslag (geen Accessibility-permissie nodig,
/// want het instellingenvenster is dan key). Esc annuleert, ⌫ wist.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?
    var lang: Lang

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Text(label)
                    .frame(minWidth: 130)
                    .foregroundStyle(recording ? Color.accentColor : .primary)
            }
            .help(L("Klik en druk een combinatie met ⌘, ⌥ of ⌃",
                    "Click and press a combination with ⌘, ⌥ or ⌃", lang))

            if shortcut != nil && !recording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("Sneltoets wissen", "Clear shortcut", lang))
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if recording { return L("Druk een combinatie…", "Press a combination…", lang) }
        return shortcut?.displayString ?? L("Geen sneltoets", "No shortcut", lang)
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard recording else { return event }
            if event.type == .flagsChanged { return nil } // modifiers alleen → negeren

            // Escape (zonder modifiers) annuleert; ⌫/⌦ wist.
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 0x35, mods.isEmpty { stop(); return nil }            // Esc
            if (event.keyCode == 0x33 || event.keyCode == 0x75), mods.isEmpty {       // Delete
                shortcut = nil; stop(); return nil
            }

            if let captured = KeyShortcut.from(event: event) {
                shortcut = captured
                stop()
            }
            // Zonder geldige modifier blijven we wachten; in alle gevallen de toets
            // opslokken zodat er niets getypt wordt.
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
