import AppKit
import UserNotifications
import CoreGraphics

/// Geluidskeuzes voor waarschuwingen + helpers om ze af te spelen, en om te
/// bepalen of het scherm vergrendeld is.
enum AlertSound {
    static let defaultChoice = "default"
    static let noneChoice = "none"

    /// macOS-systeemgeluiden (in /System/Library/Sounds) die we via NSSound spelen.
    static let systemNames = [
        "Glass", "Ping", "Submarine", "Hero", "Funk", "Sosumi",
        "Tink", "Pop", "Blow", "Bottle", "Frog", "Purr", "Morse", "Basso"
    ]

    /// Alle keuzes voor de picker: standaard, systeemgeluiden, of geen.
    static var allChoices: [String] { [defaultChoice] + systemNames + [noneChoice] }

    static func label(_ choice: String, _ lang: Lang) -> String {
        switch choice {
        case defaultChoice: return L("Standaard", "Default", lang)
        case noneChoice:    return L("Geen", "None", lang)
        default:            return choice
        }
    }

    /// Speelt het gekozen geluid zelf af — werkt ook bij een vergrendeld scherm
    /// omdat het app-proces gewoon doordraait. Notificaties zijn zelf stil
    /// (`content.sound = nil`); Bonk regelt het geluid hier, voor álle alertstijlen.
    static func play(_ choice: String) {
        switch choice {
        case noneChoice:    return
        case defaultChoice: NSSound.beep()   // het door de gebruiker ingestelde systeem-waarschuwingsgeluid
        default:            NSSound(named: NSSound.Name(choice))?.play()
        }
    }

    /// Preview vanuit de instellingen.
    static func preview(_ choice: String) { play(choice) }

    /// Is het scherm op dit moment vergrendeld?
    static var screenIsLocked: Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Int) == 1
    }
}
