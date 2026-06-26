import AppKit
import SwiftUI

/// Panel voor één pill: non-activating (steelt geen focus), boven fullscreen-apps,
/// en niet door AppKit naar het hoofdscherm/onder de menubalk geklemd.
final class PillPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Eén pill = één venster met z'n SwiftUI-inhoud.
private final class Pill {
    let pillID: String
    let panel: PillPanel
    init(id: String, rootView: some View) {
        pillID = id
        // NSHostingView (géén contentViewController/sizingOptions): vaste maat uit
        // `fittingSize`. Dat vermijdt de auto-layout-recursie die `sizingOptions`
        // kon veroorzaken, en de pill heeft één-regelige tekst dus de maat is stabiel.
        let host = NSHostingView(rootView: AnyView(rootView))
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        if size.width < 1 || size.height < 1 { size = NSSize(width: 440, height: 56) }
        panel = PillPanel(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.level = .screenSaver
    }
}

/// Toont subtiele pills boven aan het actieve scherm, gestapeld. Volgt het scherm
/// waar je werkt (klik = muis-scherm, app-wissel = voorste-venster-scherm), drijft
/// over fullscreen-apps, en steelt geen toetsenbordfocus.
@MainActor
final class PillController {
    private var pills: [Pill] = []
    private var currentScreen: NSScreen?
    private var clickMonitor: Any?
    private var observing = false
    private let topGap: CGFloat = 6
    private let spacing: CGFloat = 8

    /// Toon een pill voor een afspraak/herinnering (dedupt op id).
    func show(event: UpcomingEvent,
              accent: Color,
              lang: Lang,
              colorScheme: ColorScheme?,
              onJoin: @escaping () -> Void,
              onSnooze: @escaping (Int) -> Void,
              onSnoozeUntilStart: @escaping () -> Void,
              onDismiss: @escaping () -> Void,
              onOpenCalendar: @escaping () -> Void) {
        let id = event.id
        guard !pills.contains(where: { $0.pillID == id }) else { return }
        startObservingIfNeeded()

        let view = PillCardView(
            event: event, accent: accent, lang: lang,
            onJoin: { [weak self] in onJoin(); self?.remove(id: id) },
            onSnooze: { [weak self] (m: Int) in onSnooze(m); self?.remove(id: id) },
            onSnoozeUntilStart: { [weak self] in onSnoozeUntilStart(); self?.remove(id: id) },
            onDismiss: { [weak self] in onDismiss(); self?.remove(id: id) },
            onOpenCalendar: onOpenCalendar      // pill blijft staan na openen-in-agenda
        )
        .preferredColorScheme(colorScheme)

        let pill = Pill(id: id, rootView: view)
        pills.append(pill)
        layout(animated: false)   // grootte staat al vast → meteen correct gecentreerd
        appear(pill)
    }

    private var dying: [Pill] = []

    func remove(id: String) {
        guard let idx = pills.firstIndex(where: { $0.pillID == id }) else { return }
        let pill = pills.remove(at: idx)   // METEEN uit de array → reflow klopt direct
        dying.append(pill)
        let o = pill.panel.frame.origin
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            pill.panel.animator().alphaValue = 0
            pill.panel.animator().setFrameOrigin(NSPoint(x: o.x, y: o.y - 16))
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.cleanupDying() }
        })
        layout(animated: true)   // de rest schuift meteen op (parallel aan de fade-out)
    }

    private func cleanupDying() {
        dying.forEach { $0.panel.orderOut(nil) }
        dying.removeAll()
    }

    func removeAll() {
        pills.forEach { $0.panel.orderOut(nil) }
        pills.removeAll()
    }

    // MARK: scherm-detectie

    private func mouseScreen() -> NSScreen? {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) }
    }
    private func screen(forCG rect: CGRect) -> NSScreen? {
        let primaryH = (NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height) ?? NSScreen.main?.frame.height ?? 0
        let c = NSPoint(x: rect.midX, y: primaryH - rect.midY)
        return NSScreen.screens.first { NSMouseInRect(c, $0.frame, false) }
    }
    /// Scherm van het voorste venster van de voorste app (TCC-vrij; geen Accessibility).
    private func frontWindowScreen() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let wd = b["Width"], let ht = b["Height"] else { continue }
            if let s = screen(forCG: CGRect(x: x, y: y, width: wd, height: ht)) { return s }
        }
        return nil
    }

    private func startObservingIfNeeded() {
        guard !observing else { return }
        observing = true
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.follow(self?.mouseScreen()) }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.follow(self?.frontWindowScreen()) } }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.layout(animated: false) } }
    }

    /// Verhuis alle pills naar een ander scherm: fade out → spring (DIRECT; een
    /// geanimeerde cross-display verplaatsing klemt het venster terug) → fade in.
    private func follow(_ screen: NSScreen?) {
        guard !pills.isEmpty, let screen, screen.frame != currentScreen?.frame else { return }
        currentScreen = screen   // alvast zetten; finishFollow plaatst direct op het nieuwe scherm
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            pills.forEach { $0.panel.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishFollow() }
        })
    }

    private func finishFollow() {
        layout(animated: false)   // direct op het (al gezette) nieuwe scherm
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22; ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pills.forEach { $0.panel.animator().alphaValue = 1 }
        }
    }

    /// Plaats alle pills top-down op het actieve scherm.
    private func layout(animated: Bool) {
        guard let screen = currentScreen ?? mouseScreen() ?? NSScreen.main else { return }
        currentScreen = screen
        let vf = screen.visibleFrame
        var top = vf.maxY - topGap
        for pill in pills {
            let s = pill.panel.frame.size
            let origin = NSPoint(x: vf.midX - s.width / 2, y: top - s.height)
            // `setFrame(_:display:animate:)` is de betrouwbare window-animatie-API;
            // `animator().setFrameOrigin` beweegt deze floating-panels niet.
            if animated {
                pill.panel.setFrame(NSRect(origin: origin, size: s), display: true, animate: true)
            } else {
                pill.panel.setFrameOrigin(origin)
            }
            top = origin.y - spacing
        }
    }

    /// Verschijnen: alleen fade in. (Géén positie-slide — `layout()` is de enige
    /// die posities zet; anders vechten ze en lopen de tussenruimtes scheef.)
    private func appear(_ pill: Pill) {
        pill.panel.alphaValue = 0
        pill.panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25; ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pill.panel.animator().alphaValue = 1
        }
    }
}
