import Foundation

/// Hoe een meeting onder de aandacht wordt gebracht.
enum AlertStyle: String, Codable, CaseIterable, Identifiable {
    case fullScreen
    case banner
    case ignore

    var id: String { rawValue }

    func label(_ lang: Lang) -> String {
        switch self {
        case .fullScreen: return L("Schermvullend", "Full screen", lang)
        case .banner:     return L("Notificatie", "Notification", lang)
        case .ignore:     return L("Negeren", "Ignore", lang)
        }
    }
}
