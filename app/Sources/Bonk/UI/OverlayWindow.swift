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
@MainActor
final class OverlayController {
    private var windows: [NSWindow] = []
    private var screens: [NSScreen] = []
    private var contentIndex = 0          // index van het hoofdscherm in `screens`
    private var meetings: [OverlayMeeting] = []
    private var backdrops: [CGDirectDisplayID: NSImage] = [:]
    private var lang: Lang = .nl

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
        ensureWindows()
        render()
        NSApp.activate(ignoringOtherApps: true)
        if windows.indices.contains(contentIndex) {
            windows[contentIndex].makeKeyAndOrderFront(nil)
        }
        windows.forEach { $0.orderFrontRegardless() }
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

    private func ensureWindows() {
        guard windows.isEmpty else { return }
        screens = NSScreen.screens
        let mainScreen = NSScreen.main
        contentIndex = screens.firstIndex { $0 == mainScreen } ?? 0

        for screen in screens {
            let win = KeyableWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.level = .screenSaver
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.isReleasedWhenClosed = false
            win.setFrame(screen.frame, display: true)
            windows.append(win)
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
