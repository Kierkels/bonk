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

    private static var loopingSound: NSSound?
    private static var loopStop: DispatchWorkItem?
    private static var audioToRestore: SystemAudio.State?   // vorige mute/volume om te herstellen
    private static var restoreWork: DispatchWorkItem?

    /// Speelt het gekozen geluid zelf af — werkt ook bij een vergrendeld scherm
    /// omdat het app-proces gewoon doordraait. Notificaties zijn zelf stil
    /// (`content.sound = nil`); Bonk regelt het geluid hier, voor álle alertstijlen.
    /// - Parameters:
    ///   - repeating: herhaal het geluid (als alarm) tot `stop()` of `maxSeconds`.
    ///   - forceAudible: haal de Mac tijdelijk uit mute / zet het volume omhoog, en herstel daarna.
    static func play(_ choice: String, repeating: Bool = false, maxSeconds: Double = 30, forceAudible: Bool = false) {
        stop()
        guard choice != noneChoice else { return }

        if forceAudible { audioToRestore = SystemAudio.forceAudible() }

        if repeating {
            // NSSound.beep() kan niet loopen → gebruik een herhaalbaar systeemgeluid.
            let name = (choice == defaultChoice) ? "Sosumi" : choice
            guard let sound = NSSound(named: NSSound.Name(name)) else { NSSound.beep(); return }
            sound.loops = true
            sound.play()
            loopingSound = sound
            let work = DispatchWorkItem { stop() }
            loopStop = work
            DispatchQueue.main.asyncAfter(deadline: .now() + maxSeconds, execute: work)
        } else {
            let sound: NSSound? = (choice == defaultChoice) ? NSSound(named: "Sosumi") : NSSound(named: NSSound.Name(choice))
            if choice == defaultChoice, sound == nil { NSSound.beep() } else { sound?.play() }
            // Eenmalig geluid: herstel het volume kort na afspelen.
            if audioToRestore != nil {
                let duration = (sound?.duration ?? 1.0) + 0.4
                let work = DispatchWorkItem { restoreAudio() }
                restoreWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
            }
        }
    }

    /// Stopt een eventueel herhalend geluid en herstelt het volume.
    static func stop() {
        loopStop?.cancel(); loopStop = nil
        loopingSound?.stop(); loopingSound = nil
        restoreAudio()
    }

    private static func restoreAudio() {
        restoreWork?.cancel(); restoreWork = nil
        if let state = audioToRestore { SystemAudio.restore(state); audioToRestore = nil }
    }

    /// Preview vanuit de instellingen (eenmalig, nooit herhalend).
    static func preview(_ choice: String) { play(choice, repeating: false) }

    /// Is het scherm op dit moment vergrendeld?
    static var screenIsLocked: Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Int) == 1
    }
}
