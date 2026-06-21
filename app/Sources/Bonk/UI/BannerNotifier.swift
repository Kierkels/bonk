import Foundation
import UserNotifications

/// De subtiele variant: een gewone macOS-notificatie die je moet wegklikken.
enum BannerNotifier {
    static let joinCategory = "MEETING_JOIN"
    static let plainCategory = "MEETING"
    static let updateCategory = "BONK_UPDATE"
    static let joinAction = "JOIN"
    static let dismissAction = "DISMISS"
    static let updateAction = "OPEN_UPDATE"

    static func requestAuth(lang: Lang) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let join = UNNotificationAction(identifier: joinAction, title: L("Joinen", "Join", lang), options: [.foreground])
        let dismiss = UNNotificationAction(identifier: dismissAction, title: L("Negeren", "Ignore", lang), options: [])
        let withJoin = UNNotificationCategory(identifier: joinCategory,
                                              actions: [join, dismiss],
                                              intentIdentifiers: [],
                                              options: [.customDismissAction])
        let plain = UNNotificationCategory(identifier: plainCategory,
                                           actions: [dismiss],
                                           intentIdentifiers: [],
                                           options: [.customDismissAction])
        let download = UNNotificationAction(identifier: updateAction,
                                            title: L("Downloaden", "Download", lang),
                                            options: [.foreground])
        let update = UNNotificationCategory(identifier: updateCategory,
                                            actions: [download],
                                            intentIdentifiers: [],
                                            options: [])
        center.setNotificationCategories([withJoin, plain, update])
    }

    /// Meldt dat er een nieuwe versie van Bonk klaarstaat.
    static func showUpdate(version: String, url: URL?, lang: Lang) {
        let content = UNMutableNotificationContent()
        content.title = L("Nieuwe versie van Bonk", "New version of Bonk", lang)
        content.body = L("Versie \(version) is beschikbaar. Klik om te downloaden.",
                         "Version \(version) is available. Click to download.", lang)
        content.sound = .default
        content.categoryIdentifier = updateCategory
        if let url { content.userInfo = ["updateURL": url.absoluteString] }
        let req = UNNotificationRequest(identifier: "bonk.update.\(version)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    static func show(event: UpcomingEvent, lang: Lang) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.subtitle = L("Begint zo", "Starting soon", lang)
        content.body = event.joinURL != nil
            ? L("Klik om te joinen", "Click to join", lang)
            : L("Komt eraan", "Coming up", lang)
        content.sound = nil                          // geluid speelt Bonk zelf af (AlertSound.play)
        content.interruptionLevel = .timeSensitive   // prominenter op lock screen / bij Focus
        content.categoryIdentifier = event.joinURL != nil ? joinCategory : plainCategory
        if let url = event.joinURL {
            content.userInfo = ["joinURL": url.absoluteString]
        }
        let req = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
