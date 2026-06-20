import SwiftUI
import AppKit

/// Achtergrond-stijl voor het schermvullende overlay.
enum OverlayBackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case gradient
    case blur
    case image
    case solid

    var id: String { rawValue }

    func label(_ lang: Lang) -> String {
        switch self {
        case .gradient: return L("Gradient", "Gradient", lang)
        case .blur:     return L("Geblurd scherm", "Blurred screen", lang)
        case .image:    return L("Afbeelding", "Image", lang)
        case .solid:    return L("Effen kleur", "Solid colour", lang)
        }
    }
}

/// Een herbruikbare weergave-preset voor het schermvullende overlay.
struct OverlayAppearance: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String = "Standaard"
    var style: OverlayBackgroundStyle = .gradient
    var accentHex: String = "#5A0FB0"   // basis voor gradient / effen kleur
    var imagePath: String? = nil
    var scrim: Double = 0.25            // 0...0.8 — verdonkeren voor leesbaarheid
    var blurRadius: Double = 18         // 0...60 — sterkte van de scherm-blur

    // Wat tonen op het scherm (titel staat er altijd):
    var showCountdown: Bool = true
    var showTime: Bool = true
    var showCalendar: Bool = true
    var showAccepted: Bool = true
    var showLocation: Bool = true
    var showDescription: Bool = true

    static let `default` = OverlayAppearance()

    init(id: UUID = UUID(),
         name: String = "Standaard",
         style: OverlayBackgroundStyle = .gradient,
         accentHex: String = "#5A0FB0",
         imagePath: String? = nil,
         scrim: Double = 0.25,
         blurRadius: Double = 18,
         showCountdown: Bool = true,
         showTime: Bool = true,
         showCalendar: Bool = true,
         showAccepted: Bool = true,
         showLocation: Bool = true,
         showDescription: Bool = true) {
        self.id = id
        self.name = name
        self.style = style
        self.accentHex = accentHex
        self.imagePath = imagePath
        self.scrim = scrim
        self.blurRadius = blurRadius
        self.showCountdown = showCountdown
        self.showTime = showTime
        self.showCalendar = showCalendar
        self.showAccepted = showAccepted
        self.showLocation = showLocation
        self.showDescription = showDescription
    }

    // Migratie-bestendig: ontbrekende velden vallen terug op de default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Standaard"
        style = try c.decodeIfPresent(OverlayBackgroundStyle.self, forKey: .style) ?? .gradient
        accentHex = try c.decodeIfPresent(String.self, forKey: .accentHex) ?? "#5A0FB0"
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        scrim = try c.decodeIfPresent(Double.self, forKey: .scrim) ?? 0.25
        blurRadius = try c.decodeIfPresent(Double.self, forKey: .blurRadius) ?? 18
        showCountdown = try c.decodeIfPresent(Bool.self, forKey: .showCountdown) ?? true
        showTime = try c.decodeIfPresent(Bool.self, forKey: .showTime) ?? true
        showCalendar = try c.decodeIfPresent(Bool.self, forKey: .showCalendar) ?? true
        showAccepted = try c.decodeIfPresent(Bool.self, forKey: .showAccepted) ?? true
        showLocation = try c.decodeIfPresent(Bool.self, forKey: .showLocation) ?? true
        showDescription = try c.decodeIfPresent(Bool.self, forKey: .showDescription) ?? true
    }

    /// Korte omschrijving van de stijl voor in lijsten.
    func styleSummary(_ lang: Lang) -> String {
        switch style {
        case .gradient: return L("Gradient", "Gradient", lang)
        case .solid:    return L("Effen kleur", "Solid colour", lang)
        case .blur:     return L("Geblurd scherm · sterkte \(Int(blurRadius))", "Blurred screen · strength \(Int(blurRadius))", lang)
        case .image:    return imagePath.map { ($0 as NSString).lastPathComponent } ?? L("Afbeelding", "Image", lang)
        }
    }
}

// MARK: - Kleur-helpers

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b: UInt64
        if s.count == 6 {
            (r, g, b) = (value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        } else {
            (r, g, b) = (90, 15, 176)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Meng deze kleur met een andere NSColor (0 = ongewijzigd, 1 = volledig de andere).
    func blended(with other: NSColor, fraction: CGFloat) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return Color(ns.blended(withFraction: fraction, of: other) ?? ns)
    }
}
