import AppKit
import SwiftUI

/// Borderless venster dat focus mag pakken (nodig voor klikbare knoppen).
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Eén meeting die op het schermvullende overlay staat, met eigen acties.
struct OverlayMeeting: Identifiable {
    let id: String
    let event: UpcomingEvent
    let appearance: OverlayAppearance
    let onJoin: () -> Void
    let onSnooze: (Int) -> Void
    let onDismiss: () -> Void
}

/// Toont een schermvullend overlay over álle schermen: het hoofdscherm toont de
/// melding, de overige schermen alleen het achtergrond-effect.
///
/// Robuust tegen lock/sleep/unlock en schermherconfiguratie: bij elke wijziging
/// worden de vensters opnieuw uitgelijnd op de actuele schermen en wordt het
/// hoofdscherm (de inhoud) opnieuw gekozen. Dat voorkomt scheve vensters en het
/// "beide schermen geblurd zonder knoppen"-probleem na unlocken.
@MainActor
final class OverlayController {
    private var windows: [NSWindow] = []
    private var screens: [NSScreen] = []
    private var contentIndex = 0          // index van het hoofdscherm in `screens`
    private var meetings: [OverlayMeeting] = []
    private var backdrops: [CGDirectDisplayID: NSImage] = [:]
    private var lang: Lang = .nl
    private var observing = false

    func show(event: UpcomingEvent,
              rule: MeetingRule,
              appearance: OverlayAppearance,
              lang: Lang = .nl,
              backdrops: [CGDirectDisplayID: NSImage] = [:],
              onJoin: @escaping () -> Void,
              onSnooze: @escaping (Int) -> Void,
              onDismiss: @escaping () -> Void) {
        self.lang = lang
        guard !meetings.contains(where: { $0.id == event.id }) else { return }
        for (key, value) in backdrops { self.backdrops[key] = value }

        let id = event.id
        meetings.append(OverlayMeeting(
            id: id,
            event: event,
            appearance: appearance,
            onJoin: { [weak self] in onJoin(); self?.remove(id) },
            onSnooze: { [weak self] mins in onSnooze(mins); self?.remove(id) },
            onDismiss: { [weak self] in onDismiss(); self?.remove(id) }
        ))
        startObservingIfNeeded()
        relayout()
        // Frames kunnen na een wake/unlock pas even later kloppen → kort her-uitlijnen.
        reassertSoon()
    }

    private func remove(_ id: String) {
        meetings.removeAll { $0.id == id }
        if meetings.isEmpty { close() } else { render() }
    }

    private func closeAll() { close() }

    private func close() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        screens = []
        meetings = []
        backdrops = [:]
    }

    // MARK: - Stabiliteit: opnieuw uitlijnen bij scherm-/sessiewijzigingen

    private func startObservingIfNeeded() {
        guard !observing else { return }
        observing = true

        // Schermconfiguratie (resolutie, aansluiten/loskoppelen, lock/unlock).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.relayoutIfVisible() } }

        // Wake uit sleep.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.relayoutIfVisible() }
            }
        }

        // Scherm ontgrendeld (na lock screen).
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.relayoutIfVisible() } }
    }

    private func relayoutIfVisible() {
        guard !meetings.isEmpty else { return }
        relayout()
        reassertSoon()
    }

    /// Lijn ná korte vertraging nog eens uit — schermframes settelen na wake/unlock
    /// soms pas na de notificatie.
    private func reassertSoon() {
        for delay in [0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !self.meetings.isEmpty else { return }
                self.relayout()
            }
        }
    }

    /// Zorg dat er per actueel scherm precies één venster is, met de juiste frame,
    /// niveau en gedrag, en dat de inhoud op het huidige hoofdscherm staat.
    private func relayout() {
        let current = NSScreen.screens
        guard !current.isEmpty else { return }

        if windows.count != current.count {
            rebuildWindows(count: current.count)
        }
        screens = current
        contentIndex = current.firstIndex(where: { $0 == NSScreen.main }) ?? 0

        for (index, screen) in current.enumerated() where windows.indices.contains(index) {
            let win = windows[index]
            win.setFrame(screen.frame, display: true)
            win.level = .screenSaver
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        }

        render()

        NSApp.activate(ignoringOtherApps: true)
        if windows.indices.contains(contentIndex) {
            windows[contentIndex].makeKeyAndOrderFront(nil)
        }
        windows.forEach { $0.orderFrontRegardless() }
    }

    private func rebuildWindows(count: Int) {
        windows.forEach { $0.orderOut(nil) }
        windows = (0..<count).map { _ in
            let win = KeyableWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.isReleasedWhenClosed = false
            return win
        }
    }

    private func render() {
        let background = meetings.first?.appearance ?? .default
        for (index, screen) in screens.enumerated() {
            guard windows.indices.contains(index) else { continue }
            let backdrop = screen.bonkDisplayID.flatMap { backdrops[$0] }
            let root: AnyView
            if index == contentIndex {
                root = AnyView(OverlayContainerView(
                    meetings: meetings,
                    background: background,
                    backdrop: backdrop,
                    lang: lang,
                    onCloseAll: { [weak self] in self?.closeAll() }
                ))
            } else {
                root = AnyView(
                    OverlayBackgroundView(appearance: background, blurImage: backdrop)
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                )
            }
            windows[index].contentView = NSHostingView(rootView: root)
        }
    }
}
