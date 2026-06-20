import Foundation
import UserNotifications

/// De subtiele variant: een gewone macOS-notificatie die je moet wegklikken.
enum BannerNotifier {
    static let joinCategory = "MEETING_JOIN"
    static let plainCategory = "MEETING"
    static let joinAction = "JOIN"
    static let dismissAction = "DISMISS"

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
        center.setNotificationCategories([withJoin, plain])
    }

    static func show(event: UpcomingEvent, lang: Lang) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.subtitle = L("Begint zo", "Starting soon", lang)
        content.body = event.joinURL != nil
            ? L("Klik om te joinen", "Click to join", lang)
            : L("Komt eraan", "Coming up", lang)
        content.sound = .default
        content.categoryIdentifier = event.joinURL != nil ? joinCategory : plainCategory
        if let url = event.joinURL {
            content.userInfo = ["joinURL": url.absoluteString]
        }
        let req = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
