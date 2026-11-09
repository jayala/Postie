import Foundation
import SwiftUI

/// How the process was launched. Only debug builds can run as the unit-test host or the
/// selection regression harness; release builds are always `.normal`.
private enum LaunchMode {
    case normal
    #if DEBUG
    case unitTests
    case selectionRegression
    #endif

    static var current: LaunchMode {
        #if DEBUG
        if ProcessInfo.processInfo.environment["POSTIE_UNIT_TESTS"] == "1" { return .unitTests }
        if ProcessInfo.processInfo.arguments.contains("-PostieSelectionRegression") { return .selectionRegression }
        #endif
        return .normal
    }

    /// Hosted unit tests and the regression harness must not read the real Keychain, restore an account or make Gmail requests.
    var usesLocalAccount: Bool {
        #if DEBUG
        self != .normal
        #else
        false
        #endif
    }
}

/// Postie keeps running when its window closes, like Mail, so it can go on telling you about new mail.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct PostieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var hub: MailHub
    @State private var service: MailService
    @State private var updater: UpdaterModel
    private let launchMode = LaunchMode.current

    init() {
        let launchMode = LaunchMode.current
        let accounts = launchMode.usesLocalAccount ? AccountStore(vault: MemoryAccountVault()) : AccountStore()
        let preferences: UserDefaults? = launchMode.usesLocalAccount ? nil : .standard
        // This build is signed with its own team and bundle ID, so it must not update itself from the upstream releases.
        _updater = State(initialValue: UpdaterModel(startingUpdater: false))
        let hub = MailHub(
            accounts: accounts, persistsMail: !launchMode.usesLocalAccount, syncsInBackground: !launchMode.usesLocalAccount,
            preferences: preferences
        )
        let service = MailService(hub: hub, preferences: preferences)
        _hub = State(initialValue: hub)
        _service = State(initialValue: service)
        // The unit-test host and the regression harness have no accounts to open, and must not badge the Dock or post notifications.
        if !launchMode.usesLocalAccount { service.start() }
    }

    var body: some Scene {
        Window("Postie", id: "main") {
            root
                .frame(minWidth: 960, minHeight: 640)
                .modifier(MainWindowOpener(service: service))
        }
        .commands { MailCommands(updater: updater) }
        .defaultSize(width: 1200, height: 820)
        .windowResizability(.contentMinSize)
        // Also when Postie last quit with its window closed, or opens at login: a Dock icon alone would look stuck.
        .defaultLaunchBehavior(.presented)

        WindowGroup("New message", id: "composer", for: ComposeDraft.self) { $draft in
            if let draft {
                ComposerView(draft: draft, drafts: hub.draftStorage, send: hub.send,
                             accounts: hub.sendingAccounts, suggestContacts: hub.contacts, signature: hub.signature)
            }
        }
        .defaultSize(width: 720, height: 600)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(hub: hub, service: service)
                .environment(updater)
        }
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if launchMode == .selectionRegression {
            GmailSelectionRegressionView()
        } else {
            MailRootView(hub: hub)
        }
        #else
        MailRootView(hub: hub)
        #endif
    }
}

/// Lets a clicked notification bring the window back after it was closed, which only a view's `openWindow` can do.
private struct MainWindowOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let service: MailService

    func body(content: Content) -> some View {
        content.onAppear { service.openMainWindow = { [openWindow] in openWindow(id: "main") } }
    }
}
