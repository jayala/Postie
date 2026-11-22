import AppKit
import SwiftUI

/// The Gmail reader: folders, the conversation list and the open conversation.
/// What it does with them lives in `InboxModel`; the columns are their own views.
struct GmailInboxView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appearsActive) private var appearsActive
    @State private var screensAwake = true
    @State private var model: InboxModel
    @FocusState private var listIsFocused: Bool
    @FocusState private var searchIsFocused: Bool
    @AppStorage(SettingsKey.readingPaneLayout) private var layout = ReadingPaneLayout.defaultLayout
    /// The conversation last open, for the list to scroll back to when it returns in place of the conversation.
    @State private var lastOpenedKey: ConversationKey?

    init(hub: MailHub) {
        _model = State(initialValue: InboxModel(hub: hub))
    }

    private var hub: MailHub { model.hub }

    private var readerIsActive: Bool { scenePhase == .active && appearsActive && screensAwake }

    private var mailboxSelection: Binding<MailboxSelection?> {
        Binding(
            get: { hub.selection },
            set: { selection in
                if let selection { model.show(selection) }
            }
        )
    }

    private struct MailboxRequest: Hashable {
        let mailbox: Mailbox
        let accounts: [String]
    }

    private struct SelectionRequest: Hashable {
        let id: ConversationKey?
        let mailboxVersion: Int
        let retry: Int
        let readerIsActive: Bool
    }

    private var sidebar: some View {
        MailboxSidebar(
            selection: mailboxSelection, showsAllInboxes: hub.canShowAllInboxes, allInboxesBadge: hub.unreadInboxCount ?? 0,
            badges: [.inbox: hub.selectedUnreadInboxCount ?? 0, .drafts: hub.draftCount, .outbox: hub.outboxCount],
            labels: hub.labelTree,
            labelGroupExpansion: { path in
                Binding(get: { hub.isLabelGroupExpanded(path) }, set: { hub.setLabelGroup(path, expanded: $0) })
            }
        )
        .safeAreaBar(edge: .bottom) { AccountSwitcher(model: model) }
        .navigationSplitViewColumnWidth(
            min: MailColumn.sidebar.widthRange.lowerBound, ideal: MailColumn.sidebar.defaultWidth, max: MailColumn.sidebar.widthRange.upperBound
        )
    }

    private var conversationList: some View {
        ConversationListView(model: model, listIsFocused: $listIsFocused)
    }

    /// Without a split, one open conversation takes the list's place. Several selected ones keep the list on screen.
    private var showsConversationInPlaceOfList: Bool {
        model.selectedID != nil && model.selectedCount == 1
    }

    /// The list and the conversation when they share the detail column: one above the other, or one at a time.
    @ViewBuilder private var readingColumn: some View {
        if layout == .horizontal {
            VSplitView {
                conversationList
                    .frame(minHeight: 140, idealHeight: 300)
                ConversationDetailView(model: model)
                    .frame(minHeight: 220)
            }
        } else if showsConversationInPlaceOfList {
            ConversationDetailView(model: model)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(action: model.deselect) {
                            Label("Back to List", systemImage: "chevron.backward")
                        }
                        .help("Back to List (Esc or ⌘←)")
                    }
                }
        } else {
            ConversationListView(model: model, listIsFocused: $listIsFocused, revealOnAppear: lastOpenedKey)
        }
    }

    var body: some View {
        let actions = model.mailActions
        Group {
            if layout == .vertical {
                NavigationSplitView {
                    sidebar
                } content: {
                    conversationList
                        .background { ColumnWidthKeeper(hub: hub) }
                        .navigationSplitViewColumnWidth(
                            min: MailColumn.list.widthRange.lowerBound, ideal: MailColumn.list.defaultWidth, max: MailColumn.list.widthRange.upperBound
                        )
                } detail: {
                    ConversationDetailView(model: model)
                        .navigationSplitViewColumnWidth(min: 420, ideal: 620)
                }
            } else {
                // The list and the conversation share the one column, so only the sidebar's width is kept.
                NavigationSplitView {
                    sidebar
                        .background { ColumnWidthKeeper(hub: hub, columns: [.sidebar]) }
                } detail: {
                    readingColumn
                        .navigationSplitViewColumnWidth(min: 420, ideal: 900)
                }
            }
        }
        .navigationTitle(hub.selectionTitle)
        .onChange(of: hub.openLabelIsGone) { _, isGone in
            if isGone { model.show(.folder(.inbox)) }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search")
        .searchFocused($searchIsFocused)
        .toolbar { MailToolbar(actions: actions) }
        .focusedSceneValue(\.mailActions, actions)
        // Esc and ⌘← close the open conversation, except in the search field, where Esc clears the search
        // and ⌘← moves to the start of the line.
        .background {
            Button("Close", action: model.deselect)
                .keyboardShortcut(.cancelAction).hidden()
                .disabled(searchIsFocused)
            Button("Close", action: model.deselect)
                .keyboardShortcut(.leftArrow, modifiers: .command).hidden()
                .disabled(searchIsFocused)
        }
        // Each message gets its own window, so the mailbox stays usable while writing.
        .onChange(of: model.composer) { _, draft in
            guard let draft else { return }
            openWindow(id: "composer", value: draft)
            model.composer = nil
        }
        // Also runs when an account is added, so its mail appears without choosing a folder again.
        .task(id: MailboxRequest(mailbox: hub.mailbox, accounts: hub.sessions.map(\.id))) {
            await hub.refresh()
        }
        // Searches as you type, after a short pause. A new keystroke cancels the pending request.
        .task(id: model.searchRequest) {
            guard model.applySearch() else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await hub.performSearch()
        }
        // Invalidate a pending read immediately; activity in a composer/settings window doesn't count.
        .onChange(of: readerIsActive, initial: true) {
            model.setReaderActive(readerIsActive)
        }
        .onDisappear { model.setReaderActive(false) }
        // macOS can leave the app active while the display sleeps.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in
            screensAwake = false
            model.setReaderActive(false)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)) { _ in
            screensAwake = true
        }
        .task(id: SelectionRequest(id: model.selectedID, mailboxVersion: hub.mailboxVersion,
                                   retry: model.selectionRetry, readerIsActive: readerIsActive)) {
            guard !Task.isCancelled else { return }
            model.setReaderActive(readerIsActive)
            await model.openSelection()
        }
        .onChange(of: model.conversationKeys, initial: true) {
            model.reconcileSelection()
            model.revealIfListed()
        }
        // A notification was clicked, possibly before this window had opened.
        .onChange(of: hub.revealRequest, initial: true) {
            if let request = hub.takeRevealRequest() { model.reveal(request) }
        }
        .alert("Could not open the draft", isPresented: Binding(get: { model.draftError != nil }, set: { if !$0 { model.draftError = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.draftError ?? "")
        }
        .alert("Could not forward the conversations", isPresented: Binding(get: { model.forwardError != nil }, set: { if !$0 { model.forwardError = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.forwardError ?? "")
        }
        .onChange(of: undoManager, initial: true) { _, manager in
            model.undoManager = manager
        }
        .onChange(of: model.selectedID) { _, key in
            if let key { lastOpenedKey = key }
        }
        .onChange(of: model.listFocusRequest) {
            if !searchIsFocused, model.composer == nil { listIsFocused = true }
        }
    }
}
