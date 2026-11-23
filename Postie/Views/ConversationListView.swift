import SwiftUI

/// The middle column: notices, the search header, the conversation list and its footer.
struct ConversationListView: View {
    @Bindable var model: InboxModel
    @AppStorage(SettingsKey.conversationListTextSize) private var textSize = ConversationListTextSize.defaultSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var listIsFocused: FocusState<Bool>.Binding
    /// Scrolled to and focused when the list appears, as it comes back in place of this conversation.
    var revealOnAppear: ConversationKey?

    private var hub: MailHub { model.hub }

    /// What the list is showing. A change of it replaces the list rather than updating it.
    private struct UpdateContext: Equatable {
        let selection: MailboxSelection
        let account: String?
        let query: String
        let scope: SearchScope
        let filtersUnread: Bool
    }

    private var updateContext: UpdateContext {
        UpdateContext(selection: hub.selection, account: hub.accounts.selectedAccount?.id, query: hub.searchQuery,
                      scope: hub.searchScope, filtersUnread: hub.filtersUnread)
    }

    private var listSelection: Binding<Set<ConversationKey>> {
        Binding(get: { Set(model.selectedKeys) }, set: { model.updateFromList($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(hub.notices) { notice in
                NoticeView(notice: notice, canReconnect: !hub.accounts.isBusy, retry: model.retry) {
                    hub.accounts.reconnect($0)
                }
                Divider()
            }
            if hub.isSearchActive {
                SearchHeader(query: hub.searchQuery, folderTitle: hub.selectionTitle,
                             isSearching: hub.isSearching, scope: $model.searchScope)
                Divider()
            }
            // Keep the List (and its first responder) alive across loading and empty states.
            ScrollViewReader { proxy in
                List(selection: listSelection) {
                    if hub.list.sections.isEmpty {
                        rows(hub.conversations)
                    } else {
                        ForEach(hub.list.sections) { section in
                            Section {
                                rows(section.conversations)
                            } header: {
                                // The loaded count of the last section grows as the list scrolls, so it says there is more.
                                InboxSectionHeader(section: section, hasMore: section.section == .everythingElse && hub.hasMorePages) {
                                    hub.toggleSection(section.section)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .focused(listIsFocused)
                .accessibilityIdentifier("conversationList")
                // Keep structural updates stable while rows invalidate stale native height
                // estimates. Loading indicators outside the table can still fade.
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
                .onDeleteCommand(perform: model.deleteSelection)
                .contextMenu(forSelectionType: ConversationKey.self) { keys in
                    if keys.count > 1 {
                        SeveralConversationsContextMenu(model: model, keys: model.conversationKeys.filter(keys.contains))
                            .disabled(keys.contains(where: model.isRemoving))
                    } else if let key = keys.first {
                        ConversationContextMenu(model: model, key: key)
                            .disabled(model.isRemoving(key))
                    }
                } primaryAction: { keys in
                    // Double-click, or Return: a draft or a queued message opens for editing.
                    guard keys.count == 1, let key = keys.first else { return }
                    if hub.canActOnOutboxItem(key) { model.editOutboxItem(key) } else { model.editDraft(key) }
                }
                .overlay {
                    if hub.list.isEmpty {
                        ListPlaceholder(isLoading: hub.isLoadingMailbox || hub.isRestoringCache,
                                        isSearching: hub.isSearchActive, filtersUnread: hub.filtersUnread, mailbox: hub.mailbox)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .onChange(of: model.conversationNavigationRequest) {
                    if let key = model.selectedID { proxy.scrollTo(key) }
                }
                .onAppear {
                    guard let key = revealOnAppear else { return }
                    // After the table has its rows.
                    DispatchQueue.main.async {
                        if hub.list[key] != nil { proxy.scrollTo(key, anchor: .center) }
                        listIsFocused.wrappedValue = true
                    }
                }
            }
            // Below the list, so that rows don't move under the pointer as the first one is checked.
            if model.isMarking || model.selectedCount > 1 {
                Divider()
                BatchActionBar(model: model)
            }
            if !hub.list.isEmpty {
                Divider()
                MailboxStatusView(count: hub.loadedCount, isLoading: hub.isLoadingMailbox,
                                  isLoadingMore: hub.isLoadingMore, isSearching: hub.isSearchActive)
                    .transition(.opacity)
            }
        }
        // Fade loading status without animating the native table's structural updates.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hub.isLoadingMailbox)
        .transaction(value: updateContext) { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .toolbar {
            // The only placement that stays over this column. The others join the detail column's buttons.
            ToolbarItem(placement: .navigation) {
                UnreadFilterToggle(hub: hub)
            }
            ToolbarSpacer(.fixed, placement: .navigation)
            ToolbarItem(placement: .navigation) {
                ReadingPaneLayoutMenu()
            }
        }
    }

    private func rows(_ conversations: [MergedConversation]) -> some View {
        let showsAllCheckboxes = model.isMarking || model.selectedCount > 1
        return ForEach(conversations) { item in
            MailThreadRow(thread: item.conversation.presentation(includingBodies: false, mailbox: hub.mailbox),
                          isPending: model.isRemoving(item.key), textSize: textSize,
                          checkbox: RowCheckbox(isMarked: model.isMarked(item.key), isAlwaysVisible: showsAllCheckboxes) { extending in
                              model.toggleMark(item.key, extending: extending)
                          })
                .tag(item.key)
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading) {
                    if hub.canModifyLabels(item.key), !model.isRemoving(item.key) {
                        Button { model.toggleRead(item) } label: {
                            Label(item.conversation.isUnread ? String(localized: "Read") : String(localized: "Unread"),
                                  systemImage: item.conversation.isUnread ? "envelope.open" : "envelope.badge")
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    if hub.canActOnOutboxItem(item.key) {
                        Button(role: .destructive) { model.deleteOutboxItem(item.key) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    if hub.canTrash(item.key), !model.isRemoving(item.key) {
                        Button(role: .destructive) { model.remove(item.key, archiving: false) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    if hub.canArchive(item.key), !model.isRemoving(item.key) {
                        Button { model.remove(item.key, archiving: true) } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.indigo)
                    }
                }
                .onAppear { model.conversationAppeared(item.key) }
        }
    }
}

/// Under the list while several conversations are checked or selected: how many, and what can be done to all of them.
private struct BatchActionBar: View {
    let model: InboxModel

    var body: some View {
        let actions = model.mailActions
        HStack(spacing: 4) {
            Toggle(isOn: Binding(get: { model.allMarked }, set: { if $0 { model.markAll() } else { model.deselect() } })) {
                Text("Select All")
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(model.allMarked ? String(localized: "Deselect All") : String(localized: "Select All"))
            Text("\(model.selectedCount) selected")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.leading, 4)
            Spacer(minLength: 8)
            Group {
                Button { actions.archive?() } label: { Label("Archive", systemImage: "archivebox") }
                    .disabled(actions.archive == nil)
                    .help("Archive")
                Button { actions.trash?() } label: { Label("Move to Trash", systemImage: "trash") }
                    .disabled(actions.trash == nil)
                    .help("Move to Trash")
                Button { actions.toggleRead?() } label: {
                    Label(actions.selectionIsUnread ? String(localized: "Mark as Read") : String(localized: "Mark as Unread"),
                          systemImage: actions.selectionIsUnread ? "envelope.open" : "envelope.badge")
                }
                .disabled(actions.toggleRead == nil)
                .help(actions.selectionIsUnread ? String(localized: "Mark as Read") : String(localized: "Mark as Unread"))
                Button { actions.forward?() } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
                    .disabled(actions.forward == nil)
                    .help("Forward")
                Button(action: model.deselect) { Label("Deselect All", systemImage: "xmark") }
                    .help("Deselect All (Esc)")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
    }
}

/// Narrows the list to unread mail, or brings back the rest of the folder.
private struct UnreadFilterToggle: View {
    let hub: MailHub

    var body: some View {
        Toggle(isOn: Binding(get: { hub.filtersUnread }, set: { hub.showsOnlyUnread = $0 })) {
            Label("Show Only Unread", systemImage: "line.3.horizontal.decrease")
        }
        .toggleStyle(.button)
        .disabled(!hub.canFilterUnread)
        .help(hub.filtersUnread ? String(localized: "Show All Mail") : String(localized: "Show Only Unread"))
    }
}

/// A section's heading in the Priority Inbox. Clicking it collapses or expands the section.
private struct InboxSectionHeader: View {
    let section: MergedSection
    let hasMore: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .rotationEffect(section.isCollapsed ? .zero : .degrees(90))
                Text(section.section.title)
                    .fontWeight(.semibold)
                Spacer()
                Text(verbatim: hasMore ? "\(section.count)+" : "\(section.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(section.isCollapsed ? String(localized: "Collapsed") : String(localized: "Expanded"))
    }
}

private struct ConversationContextMenu: View {
    let model: InboxModel
    let key: ConversationKey

    private var hub: MailHub { model.hub }

    var body: some View {
        if hub.canModifyLabels(key), let conversation = hub.conversation(for: key) {
            let item = MergedConversation(key: key, conversation: conversation)
            Button(conversation.isUnread ? String(localized: "Mark as Read") : String(localized: "Mark as Unread"),
                   systemImage: conversation.isUnread ? "envelope.open" : "envelope.badge") { model.toggleRead(item) }
            Button(conversation.isStarred ? String(localized: "Unstar") : String(localized: "Star"),
                   systemImage: conversation.isStarred ? "star.slash" : "star") { model.toggleStar(item) }
            Button(conversation.isImportant ? String(localized: "Mark as Not Important") : String(localized: "Mark as Important"),
                   systemImage: "exclamationmark.circle") { model.toggleImportant(item) }
            Divider()
        }
        if hub.canEditDraft(key) {
            Button("Edit Draft", systemImage: "pencil") { model.editDraft(key) }
            Divider()
        }
        if hub.canActOnOutboxItem(key) {
            Button("Send Now", systemImage: "paperplane") { model.retryOutboxItem(key) }
            Button("Edit", systemImage: "pencil") { model.editOutboxItem(key) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { model.deleteOutboxItem(key) }
            Divider()
        }
        if key == model.selectedID, let open = model.openConversation {
            Button("Reply", systemImage: "arrowshape.turn.up.left") { model.respond(.reply) }
            Button("Reply All", systemImage: "arrowshape.turn.up.left.2") { model.respond(.replyAll) }
            if open.messages.allSatisfy(\.bodyLoaded) {
                Button("Forward", systemImage: "arrowshape.turn.up.right") { model.respond(.forward) }
            }
            Divider()
        }
        if hub.canArchive(key) {
            Button("Archive", systemImage: "archivebox") { model.remove(key, archiving: true) }
        }
        if hub.canTrash(key) {
            Button("Move to Trash", systemImage: "trash", role: .destructive) { model.remove(key, archiving: false) }
        }
    }
}

/// What can be done to several conversations at once.
private struct SeveralConversationsContextMenu: View {
    let model: InboxModel
    let keys: [ConversationKey]

    private var hub: MailHub { model.hub }

    var body: some View {
        if model.canToggleRead(keys) {
            let anyUnread = model.anyUnread(keys)
            Button(anyUnread ? String(localized: "Mark as Read") : String(localized: "Mark as Unread"),
                   systemImage: anyUnread ? "envelope.open" : "envelope.badge") { model.toggleRead(keys) }
            Divider()
        }
        if model.canForward(keys) {
            Button("Forward", systemImage: "arrowshape.turn.up.right") { model.forward(keys) }
            Divider()
        }
        let archivable = model.archivable(keys)
        if !archivable.isEmpty {
            Button("Archive", systemImage: "archivebox") { model.remove(archivable, archiving: true) }
        }
        if keys.allSatisfy(hub.canTrash) {
            Button("Move to Trash", systemImage: "trash", role: .destructive) { model.remove(keys, archiving: false) }
        }
        let queued = keys.filter(hub.canActOnOutboxItem)
        if !queued.isEmpty {
            Button("Delete", systemImage: "trash", role: .destructive) { queued.forEach(model.deleteOutboxItem) }
        }
    }
}

private struct ListPlaceholder: View {
    let isLoading: Bool
    let isSearching: Bool
    let filtersUnread: Bool
    let mailbox: Mailbox

    var body: some View {
        if isLoading, isSearching {
            MailActivityIndicator(title: String(localized: "Searching…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading {
            MailActivityIndicator(title: String(localized: "Loading mail…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isSearching {
            ContentUnavailableView {
                Label("No matching mail", systemImage: "magnifyingglass")
            } description: {
                Text("Try other words, or use Gmail search such as from:name or has:attachment.")
            }
        } else if filtersUnread {
            ContentUnavailableView {
                Label("No unread mail", systemImage: "line.3.horizontal.decrease")
            } description: {
                Text("Turn off the filter to see the rest of this folder.")
            }
        } else if mailbox == .outbox {
            ContentUnavailableView {
                Label("Outbox is empty", systemImage: mailbox.symbol)
            } description: {
                Text("Messages that are waiting to be sent, or could not be, appear here.")
            }
        } else {
            ContentUnavailableView {
                Label("No conversations", systemImage: mailbox.symbol)
            } description: {
                Text("Refresh to check for new mail.")
            }
        }
    }
}

private struct SearchHeader: View {
    let query: String
    let folderTitle: String
    let isSearching: Bool
    @Binding var scope: SearchScope

    var body: some View {
        HStack(spacing: 6) {
            Text("Search for “\(query)”")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)
            if isSearching {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel("Searching")
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                ScopeButton(title: folderTitle, scope: .folder, selection: $scope)
                ScopeButton(title: String(localized: "All Mail"), scope: .allMail, selection: $scope)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Search in")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// A quiet, neutral pill: the scope is secondary to the results, so it doesn't use the accent color.
private struct ScopeButton: View {
    let title: String
    let scope: SearchScope
    @Binding var selection: SearchScope

    private var isSelected: Bool { selection == scope }

    var body: some View {
        Button { selection = scope } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: Capsule())
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct NoticeView: View {
    let notice: HubNotice
    let canReconnect: Bool
    let retry: () -> Void
    let reconnect: (String) -> Void

    var body: some View {
        if notice.isError {
            GmailErrorBanner(message: notice.message, retry: retry)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(notice.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if case .reconnect(let accountID) = notice.fix {
                    Button("Reconnect Gmail") { reconnect(accountID) }
                        .disabled(!canReconnect)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct GmailErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Try Again", action: retry)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
