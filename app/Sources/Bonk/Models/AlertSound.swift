import AppKit
import UserNotifications
import CoreGraphics

/// Geluidskeuzes voor waarschuwingen + helpers om ze af te spelen, en om te
/// bepalen of het scherm vergrendeld is.
enum AlertSound {
    static let defaultChoice = "default"
    static let noneChoice = "none"
    /// Prefix voor zelfgekozen geluidsbestanden: `custom:<bestandsnaam>`.
    static let customPrefix = "custom:"

    /// macOS-systeemgeluiden (in /System/Library/Sounds) die we via NSSound spelen.
    static let systemNames = [
        "Glass", "Ping", "Submarine", "Hero", "Funk", "Sosumi",
        "Tink", "Pop", "Blow", "Bottle", "Frog", "Purr", "Morse", "Basso"
    ]

    /// Alle keuzes voor de picker: standaard, systeemgeluiden, eigen geluiden, of geen.
    static var allChoices: [String] { [defaultChoice] + systemNames + customSounds() + [noneChoice] }

    static func isCustom(_ choice: String) -> Bool { choice.hasPrefix(customPrefix) }

    static func label(_ choice: String, _ lang: Lang) -> String {
        switch choice {
        case defaultChoice: return L("Standaard", "Default", lang)
        case noneChoice:    return L("Geen", "None", lang)
        default:
            if isCustom(choice), let url = customURL(for: choice) {
                return url.deletingPathExtension().lastPathComponent
            }
            return choice
        }
    }

    // MARK: Eigen geluiden

    /// Map waarin geïmporteerde geluidsbestanden worden bewaard.
    static var customSoundsDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Bonk/Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// De keuze-strings (`custom:…`) van alle geïmporteerde geluiden, alfabetisch.
    static func customSounds() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: customSoundsDirectory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { !$0.hasDirectoryPath }
            .map { customPrefix + $0.lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Het bestand achter een `custom:`-keuze (nil voor niet-custom keuzes).
    static func customURL(for choice: String) -> URL? {
        guard isCustom(choice) else { return nil }
        let name = String(choice.dropFirst(customPrefix.count))
        return customSoundsDirectory.appendingPathComponent(name)
    }

    /// Kopieert een geluidsbestand naar de eigen-geluidenmap en geeft de keuze-string
    /// terug. Botsende namen worden van een volgnummer voorzien.
    static func importSound(from source: URL) -> String? {
        let fm = FileManager.default
        let dir = customSoundsDirectory
        var dest = dir.appendingPathComponent(source.lastPathComponent)
        if fm.fileExists(atPath: dest.path) {
            let base = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            var i = 2
            repeat {
                let name = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
                dest = dir.appendingPathComponent(name)
                i += 1
            } while fm.fileExists(atPath: dest.path)
        }
        do {
            try fm.copyItem(at: source, to: dest)
            return customPrefix + dest.lastPathComponent
        } catch {
            return nil
        }
    }

    /// Verwijdert een geïmporteerd geluidsbestand.
    static func removeCustom(_ choice: String) {
        guard let url = customURL(for: choice) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static var loopingSound: NSSound?
    private static var loopStop: DispatchWorkItem?
    private static var audioToRestore: SystemAudio.State?   // vorige mute/volume om te herstellen
    private static var restoreWork: DispatchWorkItem?

    /// Wordt aangeroepen zodra het huidige geluid stopt — handmatig via `stop()`,
    /// na `maxSeconds`, of als een eenmalig geluid vanzelf is uitgespeeld. Gebruikt
    /// door de instellingen om de afspeel/stop-knop weer terug te zetten.
    private static var onStopped: (() -> Void)?

    /// Sterke delegate die het natuurlijke einde van een geluid doorgeeft
    /// (NSSound.delegate is een zwakke referentie).
    private static let finishDelegate = SoundFinishDelegate()
    private final class SoundFinishDelegate: NSObject, NSSoundDelegate {
        func sound(_ sound: NSSound, didFinishPlaying flag: Bool) { AlertSound.stop() }
    }

    /// Speelt het gekozen geluid zelf af — werkt ook bij een vergrendeld scherm
    /// omdat het app-proces gewoon doordraait. Notificaties zijn zelf stil
    /// (`content.sound = nil`); Bonk regelt het geluid hier, voor álle alertstijlen.
    /// - Parameters:
    ///   - repeating: herhaal het geluid (als alarm) tot `stop()` of `maxSeconds`.
    ///   - forceAudible: als de Mac gedempt staat, haal 'm tijdelijk uit mute (het
    ///     ingestelde systeemvolume blijft staan) en herstel de mute daarna. Het geluid
    ///     speelt altijd op het huidige systeemvolume.
    static func play(_ choice: String, repeating: Bool = false, maxSeconds: Double = 30,
                     forceAudible: Bool = false, onStopped: (() -> Void)? = nil) {
        stop()
        guard choice != noneChoice else { onStopped?(); return }

        if forceAudible { audioToRestore = SystemAudio.unmuteTemporarily() }

        if repeating {
            // NSSound.beep() kan niet loopen → gebruik een herhaalbaar systeem- of
            // eigen geluid (default → Sosumi).
            guard let sound = resolveSound(choice, fallbackToSosumi: true) else {
                NSSound.beep(); onStopped?(); return
            }
            self.onStopped = onStopped
            sound.loops = true
            sound.delegate = finishDelegate
            sound.play()
            loopingSound = sound
            let work = DispatchWorkItem { stop() }
            loopStop = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(1, maxSeconds), execute: work)
        } else {
            guard let sound = resolveSound(choice, fallbackToSosumi: true) else {
                NSSound.beep()
                // Een piep kent geen einde-callback → zet de knop kort daarna terug.
                if let cb = onStopped { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: cb) }
                return
            }
            self.onStopped = onStopped
            // Vasthouden zodat de delegate het natuurlijke einde kan melden.
            loopingSound = sound
            sound.delegate = finishDelegate
            sound.play()
            // Eenmalig geluid: herstel de mute kort na afspelen.
            if audioToRestore != nil {
                let duration = sound.duration + 0.4
                let work = DispatchWorkItem { restoreAudio() }
                restoreWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
            }
        }
    }

    /// Laadt het NSSound voor een keuze: een eigen bestand (`custom:`) of een
    /// systeemgeluid. `default` valt terug op Sosumi (een herhaalbaar geluid).
    private static func resolveSound(_ choice: String, fallbackToSosumi: Bool) -> NSSound? {
        if isCustom(choice), let url = customURL(for: choice) {
            return NSSound(contentsOf: url, byReference: true)
        }
        let name = (choice == defaultChoice && fallbackToSosumi) ? "Sosumi" : choice
        return makeSound(name)
    }

    /// `NSSound(named:)` levert een gedeelde, gecachede instance — daarop `volume`/
    /// `loops` zetten is onbetrouwbaar. We werken daarom op een verse `copy()`.
    private static func makeSound(_ name: String) -> NSSound? {
        NSSound(named: NSSound.Name(name))?.copy() as? NSSound
    }

    /// Stopt een eventueel spelend geluid, herstelt het volume en meldt de stop.
    static func stop() {
        loopStop?.cancel(); loopStop = nil
        loopingSound?.stop(); loopingSound = nil
        restoreAudio()
        let cb = onStopped; onStopped = nil
        cb?()
    }

    private static func restoreAudio() {
        restoreWork?.cancel(); restoreWork = nil
        if let state = audioToRestore { SystemAudio.restore(state); audioToRestore = nil }
    }

    /// Preview vanuit de instellingen (eenmalig, nooit herhalend). `onStopped`
    /// wordt aangeroepen als het geluid stopt (vanzelf of via `stop()`).
    static func preview(_ choice: String, onStopped: (() -> Void)? = nil) {
        play(choice, repeating: false, onStopped: onStopped)
    }

    /// Speelt op dit moment een geluid (voor de afspeel/stop-knop).
    static var isPlaying: Bool { loopingSound?.isPlaying ?? false }

    /// Is het scherm op dit moment vergrendeld?
    static var screenIsLocked: Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Int) == 1
    }
}
