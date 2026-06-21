import Foundation
import AppKit

/// Controleert via de GitHub-releases van de repo of er een nieuwere versie
/// van Bonk is dan de geïnstalleerde, en publiceert dat naar de UI. Waarschuwt
/// daarnaast één keer per nieuwe versie met een systeemnotificatie.
@MainActor
final class UpdateChecker: ObservableObject {
    /// De nieuwste versie als die nieuwer is dan de huidige (anders nil).
    @Published private(set) var availableVersion: String?
    /// Pagina van de release om naartoe te sturen voor de download.
    @Published private(set) var releaseURL: URL?
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckFailed = false

    private let repo = "Kierkels/bonk"
    private let notifiedKey = "BonkUpdateNotifiedVersion.v1"   // al via notificatie gemeld
    private var lastCheck: Date?

    /// Huidige versie uit de bundle (CFBundleShortVersionString), bv. "1.0".
    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", htmlURL = "html_url", draft, prerelease
        }
    }

    /// Controleer hoogstens eens per `throttle` (standaard 6 uur).
    func checkIfDue(lang: Lang, throttle: TimeInterval = 6 * 3600) {
        if let last = lastCheck, Date().timeIntervalSince(last) < throttle { return }
        Task { await check(lang: lang) }
    }

    /// Haal de laatste release op en vergelijk met de huidige versie.
    /// - Parameter notify: toon een notificatie bij een (nieuwe) update.
    func check(notify: Bool = true, lang: Lang) async {
        isChecking = true
        lastCheckFailed = false
        lastCheck = Date()
        defer { isChecking = false }

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("Bonk", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                lastCheckFailed = true
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard !release.draft, !release.prerelease else { return }

            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            if Self.isNewer(latest, than: currentVersion) {
                availableVersion = latest
                releaseURL = URL(string: release.htmlURL)
                if notify { notifyOnce(version: latest, lang: lang) }
            } else {
                availableVersion = nil
            }
        } catch {
            lastCheckFailed = true
        }
    }

    /// Waarschuw maar één keer per versie (zodat het niet bij elke check terugkomt).
    private func notifyOnce(version: String, lang: Lang) {
        let already = UserDefaults.standard.string(forKey: notifiedKey)
        guard already != version else { return }
        UserDefaults.standard.set(version, forKey: notifiedKey)
        BannerNotifier.showUpdate(version: version, url: releaseURL, lang: lang)
    }

    /// Vergelijkt versies als puntgescheiden getallenreeksen ("1.2" > "1.1.9").
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let pa = parts(a), pb = parts(b)
        for i in 0 ..< max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
