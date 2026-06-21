import Foundation

/// Leest en zet het systeem-uitvoervolume (via AppleScript' `set volume`). Wordt
/// gebruikt om een alarm hoorbaar te maken als de Mac gedempt staat, en daarna
/// de oorspronkelijke staat te herstellen.
enum SystemAudio {
    struct State: Equatable {
        let volume: Int   // 0...100
        let muted: Bool
    }

    /// Maakt geluid hoorbaar als het gedempt is of (vrijwel) op nul staat.
    /// Geeft de vorige staat terug om later te herstellen — nil als er niets
    /// veranderd hoefde te worden (was al hoorbaar).
    static func forceAudible(minVolume: Int = 35) -> State? {
        guard let state = read() else { return nil }
        guard state.muted || state.volume < minVolume else { return nil }
        if state.muted { setMuted(false) }
        if state.volume < minVolume { setVolume(minVolume) }
        return state
    }

    static func restore(_ state: State) {
        setVolume(state.volume)
        setMuted(state.muted)
    }

    // MARK: AppleScript-bruggen

    static func read() -> State? {
        guard let out = run([
            "-e", "set s to (get volume settings)",
            "-e", "return (output volume of s as text) & \",\" & (output muted of s as text)"
        ]) else { return nil }
        let parts = out.split(separator: ",")
        guard parts.count == 2, let vol = Int(parts[0]) else { return nil }
        return State(volume: vol, muted: parts[1] == "true")
    }

    private static func setVolume(_ v: Int) {
        _ = run(["-e", "set volume output volume \(max(0, min(100, v)))"])
    }

    private static func setMuted(_ muted: Bool) {
        _ = run(["-e", "set volume output muted \(muted)"])
    }

    @discardableResult
    private static func run(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
