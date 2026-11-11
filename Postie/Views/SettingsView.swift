import SwiftUI

enum SettingsKey {
    static let showsDockBadge = "showsDockBadge"
    static let messageTextSize = "messageTextSize"
    static let conversationListTextSize = "conversationListTextSize"
    static let notifiesNewMail = "notifiesNewMail"
    static let usesPriorityInbox = "usesPriorityInbox"
    static let collapsedInboxSections = "collapsedInboxSections"
    static let collapsedLabelGroups = "collapsedLabelGroups"
    static let sidebarWidth = "sidebarWidth"
    static let conversationListWidth = "conversationListWidth"
}

struct SettingsView: View {
    let hub: MailHub
    let service: MailService

    var body: some View {
        TabView {
            Tab("Accounts", systemImage: "person.crop.circle") {
                AccountSettings(hub: hub)
            }
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(hub: hub, service: service)
            }
        }
        .scenePadding()
        .frame(width: 480, height: 440)
    }
}

private struct AccountSettings: View {
    let hub: MailHub
    @State private var selection: String?
    @State private var removing: AccountStore.Entry?

    private var accounts: AccountStore { hub.accounts }
    private var selectedAccount: AccountStore.Entry? { accounts.accounts.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if accounts.accounts.isEmpty {
                ContentUnavailableView {
                    Label("No Accounts", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("Add a Gmail account to read and send mail.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(accounts.accounts) { account in
                        AccountRow(account: account, isDefault: account.id == accounts.defaultAccount?.id)
                            .tag(account.id)
                            .contextMenu { menu(for: account) }
                    }
                }
                .listStyle(.bordered)
                .alternatingRowBackgrounds()
                .frame(maxHeight: .infinity)
                .accessibilityLabel("Accounts")
            }

            if let message = accounts.error {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let issue = accounts.configurationIssue {
                Text(issue)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Add Account…") { accounts.addAccount() }
                    .disabled(accounts.isBusy || accounts.configurationIssue != nil)
                if accounts.isBusy { ProgressView().controlSize(.small).accessibilityLabel("Connecting…") }
                Spacer()
                if let account = selectedAccount {
                    if account.needsReconnect {
                        Button("Reconnect") { accounts.reconnect(account.id) }
                            .disabled(accounts.isBusy)
                    }
                    Button("Make Default") { accounts.setDefault(account.id) }
                        .disabled(account.id == accounts.defaultAccount?.id)
                    Button("Remove…", role: .destructive) { removing = account }
                }
            }
        }
        .onChange(of: accounts.accounts) { _, current in
            if !current.contains(where: { $0.id == selection }) { selection = nil }
        }
        .confirmationDialog(
            removing.map { String(localized: "Remove \($0.email)?") } ?? "",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { account in
            Button("Remove Account", role: .destructive) { Task { await hub.removeAccount(account.id) } }
        } message: { _ in
            Text("Mail saved on this Mac for offline reading will be removed. Nothing is deleted from Gmail.")
        }
    }

    @ViewBuilder
    private func menu(for account: AccountStore.Entry) -> some View {
        Button("Make Default") { accounts.setDefault(account.id) }
            .disabled(account.id == accounts.defaultAccount?.id)
        if account.needsReconnect {
            Button("Reconnect") { accounts.reconnect(account.id) }
        }
        Divider()
        Button("Remove…", role: .destructive) { removing = account }
    }
}

private struct AccountRow: View {
    let account: AccountStore.Entry
    let isDefault: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.email)
                if let name = account.identity.name, !name.isEmpty {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if account.needsReconnect {
                Label("Needs sign-in", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            if isDefault {
                Text("Default")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct GeneralSettings: View {
    @Bindable var hub: MailHub
    @Bindable var service: MailService
    @AppStorage(SettingsKey.conversationListTextSize) private var listTextSize = ConversationListTextSize.defaultSize
    @Environment(UpdaterModel.self) private var updater

    private var notifier: MailNotifier { service.notifier }
    private var loginItem: LoginItem { service.loginItem }

    var body: some View {
        @Bindable var updater = updater
        @Bindable var notifier = notifier
        Form {
            Toggle(isOn: $hub.usesPriorityInbox) {
                Text("Priority Inbox")
                Text("Group the Inbox into Important and unread, Starred, and Everything else.")
            }
            Section {
                Picker("Message list text size", selection: $listTextSize) {
                    ForEach(ConversationListTextSize.range, id: \.self) { size in
                        if size == ConversationListTextSize.defaultSize {
                            Text("\(size) pt (Default)").tag(size)
                        } else {
                            Text("\(size) pt").tag(size)
                        }
                    }
                }
            } footer: {
                Text("Adjusts senders, subjects, previews, and metadata. Message body text size is controlled separately in View > Text Size.")
            }
            Section {
                Toggle(isOn: $notifier.isEnabled) {
                    Text("Notify me about new mail")
                    Text("When mail arrives in the Inbox while Postie is open, also with its window closed.")
                }
                if notifier.isEnabled, notifier.isDenied {
                    HStack {
                        Text("Notifications for Postie are turned off in System Settings.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open System Settings…", action: openNotificationSettings)
                    }
                }
                Toggle("Show unread count on the Dock icon", isOn: $service.showsDockBadge)
                Toggle(isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })) {
                    Text("Open Postie at login")
                    Text("Postie keeps running after you close its window, so it can tell you about new mail.")
                }
                if loginItem.needsApproval {
                    HStack {
                        Text("Allow Postie to open at login in System Settings.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open System Settings…", action: loginItem.openSystemSettings)
                    }
                } else if let error = loginItem.error {
                    Text(error)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
        }
        .formStyle(.grouped)
        // Either can be changed in System Settings while Postie runs.
        .task {
            loginItem.refresh()
            await notifier.refreshAuthorization()
        }
    }

    private func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") else { return }
        NSWorkspace.shared.open(url)
    }
}

#Preview("General settings") {
    let hub = MailHub(accounts: AccountStore(vault: MemoryAccountVault()), persistsMail: false, syncsInBackground: false)
    GeneralSettings(hub: hub, service: MailService(hub: hub, preferences: nil))
        .environment(UpdaterModel(startingUpdater: false))
        .scenePadding()
        .frame(width: 480, height: 560)
}
