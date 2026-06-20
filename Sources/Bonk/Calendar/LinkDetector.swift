import Foundation

/// Vist een join-link (Meet/Zoom/Teams/Webex) uit de tekstvelden van een afspraak.
enum LinkDetector {
    private static let patterns: [String] = [
        #"https://[a-zA-Z0-9.-]*meet\.google\.com/[a-zA-Z0-9-]+"#,
        #"https://[a-zA-Z0-9.-]*zoom\.us/(?:j|my|w|s)/[^\s>")']+"#,
        #"https://teams\.microsoft\.com/l/meetup-join/[^\s>")']+"#,
        #"https://teams\.live\.com/meet/[^\s>")']+"#,
        #"https://[a-zA-Z0-9.-]*webex\.com/[^\s>")']+"#,
    ]

    static func firstURL(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) {
            for pattern in patterns {
                if let url = firstMatch(pattern, in: text) { return url }
            }
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let r = Range(match.range, in: text) else { return nil }
        let raw = String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ">\"'),.;"))
        return URL(string: raw)
    }
}
