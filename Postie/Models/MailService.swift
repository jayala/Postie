import AppKit
import Observation

/// Keeps mail going whether or not the window is open. Postie stays running after its window closes,
/// like Mail, so the accounts, the Dock badge and notifications can't depend on a view being on screen.
@MainActor
@Observable
final class MailService {
    let hub: MailHub
    let notifier: MailNotifier
    let loginItem = LoginItem()
    var showsDockBadge: Bool {
        didSet { preferences?.set(showsDockBadge, forKey: SettingsKey.showsDockBadge) }
    }
    /// Brings the main window forward, opening it again if it was closed. Only a view can do that, so the window
    /// hands this over once it has appeared, and it has always appeared by the time anyone clicks a notification.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private var isStarted = false

    init(hub: MailHub, preferences: UserDefaults?) {
        self.hub = hub
        self.preferences = preferences
        notifier = MailNotifier(preferences: preferences)
        showsDockBadge = preferences?.object(forKey: SettingsKey.showsDockBadge) as? Bool ?? true
    }

    /// Unread mail, plus the messages that could not be sent.
    var dockBadgeCount: Int? {
        guard !hub.sessions.isEmpty else { return nil }
        let total = (hub.unreadInboxCount ?? 0) + hub.outbox.failedCount
        return hub.unreadInboxCount == nil && total == 0 ? nil : total
    }

    /// Opens the saved accounts and keeps everything up to date from then on, for as long as Postie runs.
    /// It must be called while launching, to hear about a notification click that launched Postie.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        notifier.listen()
        notifier.open = { [weak self] accountID, threadID in self?.show(accountID: accountID, threadID: threadID) }
        hub.onNewMail = { [weak self] accountID, mail in self?.notifier.announce(mail, accountID: accountID) }
        Task {
            // Accounts first, so a returning person never sees the welcome screen flash by.
            hub.accounts.restore()
            await hub.prepare()
            await followAccounts()
        }
        Task { await followDockBadge() }
        Task { await followNotificationPermission() }
    }

    private nonisolated struct AccountsState: Equatable, Sendable {
        let ids: [String]
        /// Accounts that need signing in again; reconnecting one changes this although the IDs stay the same.
        let disconnected: [String]
    }

    /// Keeps a session for every connected account, so one added or reconnected in Settings starts syncing
    /// even while the window is closed.
    private func followAccounts() async {
        let accounts = hub.accounts
        var last: AccountsState?
        let states = Observations {
            AccountsState(ids: accounts.accounts.map(\.id), disconnected: accounts.accounts.filter(\.needsReconnect).map(\.id))
        }
        for await state in states where state != last {
            last = state
            await hub.reconcile()
            await accounts.refreshProfilePictures()
        }
    }

    private func followDockBadge() async {
        for await count in Observations({ self.showsDockBadge ? self.dockBadgeCount : nil }) {
            DockBadge.update(unreadCount: count)
        }
    }

    /// Asks to show notifications once there is an account to notify about, rather than over the welcome screen.
    private func followNotificationPermission() async {
        for await wanted in Observations({ self.notifier.isEnabled && !self.hub.sessions.isEmpty }) where wanted {
            await notifier.requestAuthorization()
        }
    }

    /// Brings Postie forward with what a notification is about.
    private func show(accountID: String, threadID: String?) {
        NSApplication.shared.activate()
        openMainWindow?()
        hub.reveal(accountID: accountID, threadID: threadID)
    }
}
