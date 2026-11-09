import AppKit
import Observation
import UserNotifications
import os

/// Tells the person about mail that arrives while Postie runs, with macOS notifications.
/// Clicking one opens its conversation.
@MainActor
@Observable
final class MailNotifier: NSObject {
    /// More messages than this at once, such as after the Mac wakes up, get one notification between them.
    static let individualLimit = 3

    private nonisolated static let accountKey = "account"
    private nonisolated static let threadKey = "thread"

    /// Postie's own setting. macOS has its own on top, in System Settings > Notifications.
    var isEnabled: Bool {
        didSet { preferences?.set(isEnabled, forKey: SettingsKey.notifiesNewMail) }
    }
    /// Whether macOS has been told not to show Postie's notifications.
    private(set) var isDenied = false
    /// Shows what a clicked notification is about: an account's conversation, or just its Inbox.
    @ObservationIgnored var open: ((_ accountID: String, _ threadID: String?) -> Void)?

    @ObservationIgnored private let preferences: UserDefaults?

    init(preferences: UserDefaults?) {
        self.preferences = preferences
        isEnabled = preferences?.object(forKey: SettingsKey.notifiesNewMail) as? Bool ?? true
        super.init()
    }

    /// Becomes the one to hear about clicks. It has to be before launching finishes, to hear about the click that launched Postie.
    func listen() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks macOS for permission the first time. After that, it only looks up the answer.
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
        catch { Log.notifications.error("Could not ask to show notifications: \(error.localizedDescription, privacy: .public)") }
        await refreshAuthorization()
    }

    func refreshAuthorization() async {
        isDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    func announce(_ mail: [NewMail], accountID: String) {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        for (identifier, content) in Self.notifications(for: mail, accountID: accountID) {
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
                if let error { Log.notifications.error("Could not show a notification: \(error.localizedDescription, privacy: .public)") }
            }
        }
    }

    /// One notification per message, like Mail: who it is from, the subject and how it starts.
    /// Past `individualLimit`, a single one says how many arrived and from whom.
    static func notifications(for mail: [NewMail], accountID: String) -> [(identifier: String, content: UNMutableNotificationContent)] {
        guard !mail.isEmpty else { return [] }
        if mail.count <= individualLimit {
            return mail.map { message in
                let content = UNMutableNotificationContent()
                content.title = message.senderName.isEmpty ? message.senderEmail : message.senderName
                content.subtitle = message.subject
                content.body = message.snippet
                content.sound = .default
                content.threadIdentifier = accountID + "/" + message.threadID
                content.userInfo = [accountKey: accountID, threadKey: message.threadID]
                return (accountID + "/" + message.messageID, content)
            }
        }
        var senders: [String] = []
        for message in mail.reversed() {
            let name = message.senderName.isEmpty ? message.senderEmail : message.senderName
            if !senders.contains(name) { senders.append(name) }
        }
        let shown = Array(senders.prefix(individualLimit))
        let names = ListFormatter.localizedString(byJoining: senders.count > shown.count
            ? shown + [String(localized: "others", comment: "Ends the list of senders in a notification about several new messages")]
            : shown)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(mail.count) new messages",
                               comment: "Title of the notification about several messages arriving at once; always more than three")
        content.body = String(localized: "From \(names)", comment: "Body of the notification about several new messages, listing the senders")
        content.sound = .default
        content.threadIdentifier = accountID
        content.userInfo = [accountKey: accountID]
        let newest = mail.last?.messageID ?? ""
        return [(accountID + "/" + newest + "/summary", content)]
    }
}

extension MailNotifier: UNUserNotificationCenterDelegate {
    /// While Postie is the app in front, its window already shows the new mail: the notification goes straight
    /// to Notification Center, without a banner or a sound.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { NSApplication.shared.isActive } ? [.list] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        guard let accountID = info[Self.accountKey] as? String else { return }
        let threadID = info[Self.threadKey] as? String
        await MainActor.run { open?(accountID, threadID) }
    }
}
