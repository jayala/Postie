import Foundation
import Observation

/// What one Gmail reader window is doing: the selection, the search, the open composer and the
/// actions on a conversation. The views only render this; the hub owns the mail itself.
@MainActor
@Observable
final class InboxModel {
    let hub: MailHub
    var searchText = ""
    var searchScope: SearchScope = .allMail
    var composer: ComposeDraft?
    /// Why a draft could not be opened for editing.
    var draftError: String?
    /// Why the selected conversations could not be forwarded.
    var forwardError: String?
    private var isPreparingForward = false
    /// Bumped to ask the conversation to be loaded again after a failure.
    private(set) var selectionRetry = 0
    /// Bumped when an explicit removal should hand keyboard focus back to the list.
    private(set) var listFocusRequest = 0
    /// Explicit toolbar/menu navigation reveals its row without stealing focus from the reader.
    private(set) var conversationNavigationRequest = 0
    private var selection = ConversationSelection<ConversationKey>() {
        didSet { hub.holdInPlace(selection.selectedIDs) }
    }
    /// The window's history, which also backs the Edit menu and undoing typing in the search field.
    @ObservationIgnored weak var undoManager: UndoManager?
    /// The undo or redo reaching Gmail last, which the next one waits for.
    @ObservationIgnored private var undoQueue: Task<Void, Never>?

    private(set) var isReaderActive = false
    @ObservationIgnored private var readerActivityRevision = 0
    @ObservationIgnored private let autoReadDelay: @MainActor () async throws -> Void
    @ObservationIgnored private var selectionBeforeSearch: Set<ConversationKey> = []
    @ObservationIgnored private var manualUnreadRevision: Int?
    // Once a Gmail write begins it must survive view-task cancellation during its follow-up refresh.
    @ObservationIgnored private var autoReadTasks: [ConversationKey: Task<Void, Never>] = [:]
    /// The conversation a notification opened, until its row is in the list.
    @ObservationIgnored private var pendingReveal: ConversationKey?

    init(hub: MailHub, autoReadDelay: @escaping @MainActor () async throws -> Void = {
        try await Task.sleep(for: .seconds(1))
    }) {
        self.hub = hub
        self.autoReadDelay = autoReadDelay
    }

    /// Activity belongs to the reader window, not another Postie window such as the composer.
    func setReaderActive(_ active: Bool) {
        guard isReaderActive != active else { return }
        isReaderActive = active
        readerActivityRevision += 1
        // Nobody is reading the list, so the mail read so far can go where it belongs without moving it from under them.
        if !active { hub.settleSections() }
    }

    // MARK: Selection

    var conversationKeys: [ConversationKey] { hub.conversationKeys }

    /// The conversation to open: the only selected one, as long as it is still in the list.
    var selectedID: ConversationKey? {
        selection.selectedID.flatMap { hub.list[$0] == nil ? nil : $0 }
    }

    /// Every selected conversation still in the list, in list order.
    var selectedKeys: [ConversationKey] {
        conversationKeys.filter(selection.selectedIDs.contains)
    }

    /// How many conversations are selected, counting those being removed so the count doesn't tick down meanwhile.
    var selectedCount: Int { selection.selectedIDs.count }

    func select(_ key: ConversationKey?) {
        selection.select(key)
    }

    /// Whether conversations are checked with their checkboxes rather than selected in the list. None of them is open.
    var isMarking: Bool { selection.isMarking }

    /// Whether a conversation's checkbox shows as checked.
    func isMarked(_ key: ConversationKey) -> Bool { selection.markedIDs.contains(key) }

    /// A click on a conversation's checkbox. With Shift, every conversation from the last one clicked to this one
    /// takes the same state, as in Gmail.
    func toggleMark(_ key: ConversationKey, extending: Bool) {
        if extending { selection.extendMark(to: key, visibleIDs: conversationKeys) } else { selection.toggleMark(key) }
    }

    /// Checks every conversation in the list as it is loaded so far.
    func markAll() {
        selection.mark(Set(conversationKeys))
    }

    /// Whether every conversation in the list is checked.
    var allMarked: Bool {
        let marked = selection.markedIDs
        return !conversationKeys.isEmpty && conversationKeys.allSatisfy(marked.contains)
    }

    /// Closes the open conversation. The list takes keyboard focus, which may have been inside the message.
    func deselect() {
        guard !selection.selectedIDs.isEmpty else { return }
        selection.select(nil)
        listFocusRequest += 1
    }

    func updateFromList(_ keys: Set<ConversationKey>) {
        selection.updateFromList(keys, visibleIDs: conversationKeys)
    }

    func reconcileSelection() {
        selection.reconcile(with: conversationKeys)
    }

    func navigateConversation(offset: Int) {
        guard let key = selection.neighbor(offset: offset, visibleIDs: conversationKeys) else { return }
        select(key)
        conversationNavigationRequest += 1
    }

    func show(_ target: MailboxSelection) {
        guard target != hub.selection else { return }
        startNewList()
        hub.show(target)
    }

    func selectAccount(_ id: String) {
        guard hub.isShowingAllInboxes || id != hub.accounts.selectedAccount?.id else { return }
        startNewList()
        hub.selectAccount(id)
    }

    private func startNewList() {
        selection.reset()
        searchText = ""
        selectionBeforeSearch = []
        pendingReveal = nil
    }

    /// Shows what a notification pointed at: the Inbox it arrived in, unless that is already on screen, with its
    /// conversation selected. A notification about several messages only shows the Inbox.
    func reveal(_ request: MailHub.RevealRequest) {
        let showsItsInbox = hub.mailbox == .inbox
            && (hub.isShowingAllInboxes || hub.accounts.selectedAccount?.id == request.accountID)
        if showsItsInbox {
            if !searchText.isEmpty {
                searchText = ""
                _ = applySearch()
            }
        } else {
            startNewList()
            hub.selectAccount(request.accountID)
            hub.show(.folder(.inbox))
        }
        pendingReveal = request.threadID.map { ConversationKey(accountID: request.accountID, threadID: $0) }
        revealIfListed()
    }

    /// Selects the conversation a notification opened, once the list has caught up with it.
    func revealIfListed() {
        guard let key = pendingReveal, hub.list[key] != nil else { return }
        if !conversationKeys.contains(key) {
            // Loaded but out of sight in a collapsed Priority Inbox section, which has to open for it.
            guard let section = hub.section(of: key), hub.collapsedSections.contains(section) else { return }
            hub.toggleSection(section)
        }
        pendingReveal = nil
        selection.select(key)
    }

    /// The fully loaded conversation that Reply and Forward act on. Its account is the one that sends the response.
    var openConversation: GmailConversation? {
        guard let selectedID, hub.sendingAccounts.contains(where: { $0.id == selectedID.accountID }),
              hub.mailbox != .outbox, hub.mailbox != .drafts else { return nil }
        return hub.openConversation(for: selectedID)
    }

    /// The selected conversation, when its labels can be changed.
    var selected: MergedConversation? {
        guard let selectedID, hub.canModifyLabels(selectedID),
              let conversation = hub.conversation(for: selectedID) else { return nil }
        return MergedConversation(key: selectedID, conversation: conversation)
    }

    /// Loads the selected conversation, then marks it read once it has stayed open for a moment.
    func openSelection() async {
        guard !Task.isCancelled else { return }
        let key = selectedID
        let revision = selection.revision
        let activityRevision = readerActivityRevision
        await hub.select(key)
        guard let key, !Task.isCancelled, selectedID == key, selection.revision == revision,
              isReaderActive, readerActivityRevision == activityRevision else { return }
        await markOpenedConversationRead(key, revision: revision, activityRevision: activityRevision)
    }

    func retrySelection() {
        selectionRetry += 1
    }

    /// Marks the open conversation read after it has stayed open briefly, so skimming past mail doesn't change it.
    private func markOpenedConversationRead(_ key: ConversationKey, revision: Int, activityRevision: Int) async {
        guard isReaderActive, readerActivityRevision == activityRevision, hub.canModifyLabels(key),
              manualUnreadRevision != revision, autoReadTasks[key] == nil,
              let conversation = hub.openConversation(for: key), conversation.isUnread,
              conversation.messages.allSatisfy(\.bodyLoaded) else { return }
        do { try await autoReadDelay() }
        catch { return }
        guard !Task.isCancelled, isReaderActive, readerActivityRevision == activityRevision,
              selectedID == key, selection.revision == revision,
              manualUnreadRevision != revision, autoReadTasks[key] == nil,
              hub.openConversation(for: key)?.isUnread == true else { return }

        let task = Task {
            // Recheck on entry: the window may deactivate before this unstructured task starts.
            guard isReaderActive, readerActivityRevision == activityRevision,
                  selectedID == key, selection.revision == revision, manualUnreadRevision != revision else { return }
            await hub.setUnread(key, false)
        }
        autoReadTasks[key] = task
        await task.value
        autoReadTasks[key] = nil
        // Recheck actual unread state next time: neither a failed attempt nor an earlier
        // successful read should block a newly arrived unread reply in this conversation.
    }

    // MARK: Loading

    /// Get New Mail. Like refreshing Gmail, it also puts the mail read so far in the Priority Inbox section it now fits.
    func refresh() {
        hub.settleSections()
        Task { await hub.refresh() }
    }

    /// Tries again after an error, for whatever failed: the folder, the search or both.
    func retry() {
        refresh()
        if selectedID != nil { retrySelection() }
        if hub.isSearchActive { Task { await hub.performSearch() } }
    }

    func loadMore() {
        Task { await hub.loadMore() }
    }

    /// Loads the next page as the end of the list scrolls into view.
    func conversationAppeared(_ key: ConversationKey) {
        guard key == conversationKeys.last, hub.hasMorePages, !hub.isLoadingMailbox, !hub.list.endsCollapsed else { return }
        loadMore()
    }

    // MARK: Search

    struct SearchRequest: Hashable {
        let text: String
        let scope: SearchScope
    }

    var searchRequest: SearchRequest { SearchRequest(text: searchText, scope: searchScope) }

    /// Switches the list to search mode (or back) right away. Returns whether results should now be fetched.
    func applySearch() -> Bool {
        let wasSearching = hub.isSearchActive
        let willSearch = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !wasSearching, willSearch {
            // Save identity before changing which rows the hub exposes.
            selectionBeforeSearch = selection.selectedIDs
            selection.select(nil)
        }
        hub.setSearch(searchText, scope: searchScope)
        if wasSearching, !willSearch {
            if !selectionBeforeSearch.isEmpty { selection.select(selectionBeforeSearch) }
            selectionBeforeSearch = []
            reconcileSelection()
        }
        return hub.isSearchActive
    }

    // MARK: Actions on a conversation

    func toggleRead(_ item: MergedConversation) {
        let unread = !item.conversation.isUnread
        keepUnread([item.key], unread)
        changeLabel(.setUnread([item.key], unread), named: unread ? String(localized: "Mark as Unread") : String(localized: "Mark as Read"),
                    after: [item.key].compactMap { autoReadTasks[$0] })
    }

    /// Explicit unread wins for this opening, including a countdown already in progress.
    private func keepUnread(_ keys: [ConversationKey], _ unread: Bool) {
        if unread, let selectedID, keys.contains(selectedID) { manualUnreadRevision = selection.revision }
    }

    /// Whether Mark as Read or Unread can change every one of these conversations.
    func canToggleRead(_ keys: [ConversationKey]) -> Bool {
        !keys.isEmpty && keys.allSatisfy { hub.canModifyLabels($0) && hub.conversation(for: $0) != nil }
    }

    /// Like Mail, several conversations are marked read while any of them is unread, and unread once they all are read.
    func anyUnread(_ keys: [ConversationKey]) -> Bool {
        keys.contains { hub.conversation(for: $0)?.isUnread == true }
    }

    /// Marks several conversations read or unread in one step, asking Gmail only about those that change.
    func toggleRead(_ keys: [ConversationKey]) {
        guard canToggleRead(keys) else { return }
        let unread = !anyUnread(keys)
        let changing = keys.filter { hub.conversation(for: $0)?.isUnread != unread }
        guard !changing.isEmpty else { return }
        keepUnread(changing, unread)
        changeLabel(.setUnread(changing, unread), named: unread ? String(localized: "Mark as Unread") : String(localized: "Mark as Read"),
                    after: changing.compactMap { autoReadTasks[$0] })
    }

    func toggleStar(_ item: MergedConversation) {
        let starred = !item.conversation.isStarred
        changeLabel(.setStarred(item.key, starred), named: starred ? String(localized: "Star") : String(localized: "Unstar"))
    }

    func toggleImportant(_ item: MergedConversation) {
        let important = !item.conversation.isImportant
        changeLabel(.setImportant(item.key, important),
                    named: important ? String(localized: "Mark as Important") : String(localized: "Mark as Not Important"))
    }

    private func changeLabel(_ change: MailChange, named name: String, after pending: [Task<Void, Never>] = []) {
        Task {
            // Serialize against an automatic write already sent to Gmail so the user's choice wins.
            for task in pending { await task.value }
            if await apply(change) { recordUndo(change.opposite, named: name) }
        }
    }

    func isRemoving(_ key: ConversationKey) -> Bool { selection.isRemoving(key) }

    var canRemoveSelection: Bool {
        let keys = selectedKeys
        return !keys.isEmpty && !keys.contains(where: isRemoving)
    }

    func remove(_ key: ConversationKey, archiving: Bool) {
        remove([key], archiving: archiving)
    }

    /// The ones Archive acts on. In a label or a search, some may not be in the Inbox, and only the others can be archived.
    func archivable(_ keys: [ConversationKey]) -> [ConversationKey] {
        keys.filter(hub.canArchive)
    }

    func remove(_ keys: [ConversationKey], archiving: Bool) {
        // Like Gmail, nothing opens after checked conversations go.
        guard let token = selection.beginRemoval(of: Set(keys), visibleIDs: conversationKeys,
                                                 opensNext: hub.opensNextAfterRemoval && !selection.isMarking) else { return }
        let snapshots = hub.canUndoRemoval(archiving: archiving) ? hub.removedConversations(keys) : []
        Task {
            let removed = await removeRows(keys, archiving: archiving, token: token)
            let undoable = snapshots.filter { removed.contains($0.key) }
            if !undoable.isEmpty {
                recordUndo(.restore(undoable, archived: archiving), named: Self.removalName(count: undoable.count, archiving: archiving))
            }
            await hub.refresh(after: keys, succeeded: removed)
        }
    }

    private func removeRows(_ keys: [ConversationKey], archiving: Bool, anyFolder: Bool = false, token: UUID?) async -> [ConversationKey] {
        let removed = await hub.remove(keys, archiving: archiving, anyFolder: anyFolder) { [self] in
            // An explicit selected-thread removal returns keyboard navigation to the list,
            // including when it is empty. Background sync never steals search focus.
            if let token, selection.rowRemoved(token, visibleIDs: conversationKeys) { returnFocusToList() }
        }
        // Still pending when Gmail refused some of them, and those then stay selected.
        if let token, selection.finishRemoval(token, removed: !removed.isEmpty, visibleIDs: conversationKeys) { returnFocusToList() }
        return removed
    }

    private static func removalName(count: Int, archiving: Bool) -> String {
        if count == 1 { return archiving ? String(localized: "Archive") : String(localized: "Move to Trash") }
        return archiving ? String(localized: "Archive \(count) Conversations") : String(localized: "Move \(count) Conversations to Trash")
    }

    private func returnFocusToList() {
        if composer == nil { listFocusRequest += 1 }
    }

    /// The Delete key: queued messages are deleted, anything else goes to the Trash.
    func deleteSelection() {
        let keys = selectedKeys
        let queued = keys.filter(hub.canActOnOutboxItem)
        if !queued.isEmpty { queued.forEach(deleteOutboxItem) }
        else if !keys.isEmpty, keys.allSatisfy(hub.canTrash) { remove(keys, archiving: false) }
    }

    // MARK: Undo

    /// A change to mail that can be taken back. Taking it back records its opposite, which is what Redo then does.
    private enum MailChange {
        case remove([RemovedConversation], archiving: Bool)
        case restore([RemovedConversation], archived: Bool)
        case setUnread([ConversationKey], Bool)
        case setStarred(ConversationKey, Bool)
        case setImportant(ConversationKey, Bool)

        var opposite: MailChange {
            switch self {
            case .remove(let items, let archiving): .restore(items, archived: archiving)
            case .restore(let items, let archived): .remove(items, archiving: archived)
            case .setUnread(let keys, let unread): .setUnread(keys, !unread)
            case .setStarred(let key, let starred): .setStarred(key, !starred)
            case .setImportant(let key, let important): .setImportant(key, !important)
            }
        }
    }

    /// Adds a step to the history, named for the Undo and Redo menu items.
    private func recordUndo(_ undo: MailChange, named name: String) {
        guard let undoManager else { return }
        // Gmail answers between input events, and until the next event automatic grouping would make
        // all its answers a single step. Undo and Redo have a group of their own open already.
        let needsOwnGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if needsOwnGroup {
            undoManager.groupsByEvent = false
            undoManager.beginUndoGrouping()
        }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.perform(undo, named: name) }
        }
        undoManager.setActionName(name)
        if needsOwnGroup {
            undoManager.endUndoGrouping()
            undoManager.groupsByEvent = true
        }
    }

    /// Runs when Undo or Redo is chosen. Only while it runs does the opposite step go to the other side of
    /// the history, so that cannot wait for Gmail. Gmail hears about them one at a time, in the order chosen.
    private func perform(_ change: MailChange, named name: String) {
        let isUndoing = undoManager?.isUndoing == true
        if case .setUnread(let keys, let unread) = change { keepUnread(keys, unread) }
        recordUndo(change.opposite, named: name)
        let previous = undoQueue
        undoQueue = Task {
            await previous?.value
            // Offline, say: the error is on screen and Undo can be tried again later.
            if await !apply(change), isUndoing { recordUndo(change, named: name) }
        }
    }

    /// Makes the change in Gmail and on screen. Returns once Gmail has answered, whether or not it took all of it.
    private func apply(_ change: MailChange) async -> Bool {
        let keys: [ConversationKey]
        let succeeded: [ConversationKey]
        switch change {
        case .remove(let items, let archiving):
            keys = items.map(\.key)
            let token = selection.beginRemoval(of: Set(keys), visibleIDs: conversationKeys, opensNext: hub.opensNextAfterRemoval)
            succeeded = await removeRows(keys, archiving: archiving, anyFolder: true, token: token)
        case .restore(let items, let archived):
            keys = items.map(\.key)
            succeeded = await hub.restore(items, archived: archived)
            selectRestored(succeeded)
        case .setUnread(let changed, let unread):
            keys = changed
            succeeded = await hub.setUnread(changed, unread)
        case .setStarred(let key, let starred):
            keys = [key]
            succeeded = await hub.setStarred(key, starred, refreshing: false) ? [key] : []
        case .setImportant(let key, let important):
            keys = [key]
            succeeded = await hub.setImportant(key, important, refreshing: false) ? [key] : []
        }
        // Not awaited: the next undo should not have to wait for it.
        Task { await hub.refresh(after: keys, succeeded: succeeded) }
        return succeeded.count == keys.count
    }

    /// Like Mail, what comes back is selected, provided it came back to the list on screen.
    private func selectRestored(_ keys: [ConversationKey]) {
        let visible = Set(keys).intersection(conversationKeys)
        guard !visible.isEmpty else { return }
        selection.select(visible)
        // Undo puts things back as they were, so opening one this way must not mark it read.
        if visible.count == 1 { manualUnreadRevision = selection.revision }
        returnFocusToList()
    }

    // MARK: Composing

    var canCompose: Bool { !hub.sendingAccounts.isEmpty }

    func newMessage() {
        composer = ComposeDraft(accountID: hub.defaultSendingAccount?.id)
    }

    func respond(_ kind: ComposeKind) {
        guard let key = selectedID, let conversation = openConversation,
              let accountEmail = hub.email(for: key.accountID) else { return }
        let thread = conversation.presentation(includingBodies: true, mailbox: hub.mailbox)
        var draft = kind == .forward
            ? ComposeDraft.forward(thread)
            : ComposeDraft.reply(to: thread, accountEmail: accountEmail, allRecipients: kind == .replyAll)
        draft.accountID = key.accountID
        draft.gmailThreadID = kind == .forward ? nil : key.threadID
        composer = draft
    }

    /// Whether these conversations can go out together. Unlike one open conversation, their bodies load on demand.
    func canForward(_ keys: [ConversationKey]) -> Bool {
        !isPreparingForward && !keys.isEmpty && hub.mailbox != .outbox && hub.mailbox != .drafts
            && keys.allSatisfy { key in hub.sendingAccounts.contains { $0.id == key.accountID } }
    }

    /// Forwards conversations in one message, from the account of the first of them.
    func forward(_ keys: [ConversationKey]) {
        guard canForward(keys) else { return }
        isPreparingForward = true
        Task {
            defer { isPreparingForward = false }
            do {
                var threads: [MailThread] = []
                for key in keys {
                    threads.append(try await hub.fullConversation(key).presentation(includingBodies: true, mailbox: hub.mailbox))
                }
                var draft = ComposeDraft.forward(threads)
                draft.accountID = keys.first?.accountID
                composer = draft
            } catch {
                forwardError = error.localizedDescription
            }
        }
    }

    /// Opens a draft of the Drafts folder in a composer window.
    func editDraft(_ key: ConversationKey) {
        guard hub.canEditDraft(key) else { return }
        Task {
            do {
                if let draft = try await hub.openDraft(key) { composer = draft }
            } catch {
                draftError = error.localizedDescription
            }
        }
    }

    // MARK: Outbox

    /// Takes a queued message back into a composer window to change it.
    func editOutboxItem(_ key: ConversationKey) {
        guard hub.canActOnOutboxItem(key) else { return }
        Task {
            do {
                if let draft = try await hub.editOutboxItem(key) { composer = draft }
            } catch {
                draftError = error.localizedDescription
            }
        }
    }

    func retryOutboxItem(_ key: ConversationKey) {
        hub.retryOutboxItem(key)
    }

    func deleteOutboxItem(_ key: ConversationKey) {
        guard hub.canActOnOutboxItem(key) else { return }
        Task { await hub.deleteOutboxItem(key) }
    }

    // MARK: Menu and toolbar

    var mailActions: MailActions {
        let selectedID = selectedID
        let openConversation = openConversation
        let selected = selected
        let selectedKeys = selectedKeys
        let archivable = archivable(selectedKeys)
        let hasSeveral = selectedCount > 1 || isMarking
        return MailActions(
            currentSelection: hub.selection,
            canShowAllInboxes: hub.canShowAllInboxes,
            select: { [self] in show($0) },
            newMessage: canCompose ? { [self] in newMessage() } : nil,
            refresh: hub.isLoadingMailbox || hub.mailbox == .outbox ? nil : { [self] in refresh() },
            archive: canRemoveSelection && !archivable.isEmpty
                ? { [self] in remove(archivable, archiving: true) } : nil,
            trash: canRemoveSelection && selectedKeys.allSatisfy(hub.canTrash)
                ? { [self] in remove(selectedKeys, archiving: false) } : nil,
            editDraft: selectedID.flatMap { key in hub.canEditDraft(key) ? { [self] in editDraft(key) } : nil },
            // Several conversations have no open one to answer, so only Forward stays available.
            reply: openConversation == nil ? nil : { [self] in respond(.reply) },
            replyAll: openConversation == nil ? nil : { [self] in respond(.replyAll) },
            forward: hasSeveral
                ? (canForward(selectedKeys) ? { [self] in forward(selectedKeys) } : nil)
                : (openConversation.map { $0.messages.allSatisfy(\.bodyLoaded) } == true ? { [self] in respond(.forward) } : nil),
            toggleRead: hasSeveral
                ? (canToggleRead(selectedKeys) ? { [self] in toggleRead(selectedKeys) } : nil)
                : selected.map { item in { [self] in toggleRead(item) } },
            toggleFlag: selected.map { item in { [self] in toggleStar(item) } },
            toggleImportant: selected.map { item in { [self] in toggleImportant(item) } },
            selectionIsUnread: hasSeveral ? anyUnread(selectedKeys) : selected?.conversation.isUnread ?? false,
            selectionIsFlagged: selected?.conversation.isStarred ?? false,
            selectionIsImportant: selected?.conversation.isImportant ?? false,
            previousConversation: selection.neighbor(offset: -1, visibleIDs: conversationKeys) == nil
                ? nil : { [self] in navigateConversation(offset: -1) },
            nextConversation: selection.neighbor(offset: 1, visibleIDs: conversationKeys) == nil
                ? nil : { [self] in navigateConversation(offset: 1) }
        )
    }
}
