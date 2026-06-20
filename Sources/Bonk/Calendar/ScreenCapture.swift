import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Maakt een stilstaande schermafbeelding (voor de instelbare blur-achtergrond).
/// Vereist schermopname-toestemming; faalt netjes naar `nil` als die ontbreekt.
enum ScreenCapture {
    /// Heeft het draaiende proces nu écht schermopname-toegang? (los van wat de
    /// lijst in Systeeminstellingen toont voor een mogelijk oudere build)
    static var hasAccess: Bool { CGPreflightScreenCaptureAccess() }

    /// Toont eenmalig de systeemprompt. Pas aanroepen op expliciete gebruikersactie.
    @discardableResult
    static func requestAccess() -> Bool { CGRequestScreenCaptureAccess() }

    static func capture(displayID: CGDirectDisplayID? = nil) async -> NSImage? {
        // Nooit zelf de prompt forceren: zonder toegang gewoon nil teruggeven,
        // zodat het overlay terugvalt op frosted-glass.
        guard hasAccess else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)

            let display: SCDisplay?
            if let displayID {
                display = content.displays.first { $0.displayID == displayID } ?? content.displays.first
            } else {
                display = content.displays.first
            }
            guard let display else { return nil }

            let filter = SCContentFilter(display: display,
                                         excludingApplications: [],
                                         exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            return NSImage(cgImage: cgImage,
                           size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            return nil
        }
    }

    /// Display-id van het scherm waarop het overlay komt (NSScreen.main).
    static func mainDisplayID() -> CGDirectDisplayID? {
        NSScreen.main?.bonkDisplayID
    }
}

extension NSScreen {
    var bonkDisplayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
