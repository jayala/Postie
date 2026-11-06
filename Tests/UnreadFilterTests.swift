import Foundation
import Testing
@testable import Postie

/// A synced account whose first Inbox page leaves out older unread threads.
private actor SyncedUnreadAPI: GmailSyncReading, GmailUnreadLoading {
    private let inbox: [GmailConversation]
    private let unreadPages: [[GmailConversation]]
    private(set) var unreadRequests: [Set<String>] = []

    init(inbox: [GmailConversation], unreadPages: [[GmailConversation]]) {
        self.inbox = inbox
        self.unreadPages = unreadPages
    }

    func mailbox(_ mailbox: Mailbox, pageToken: String?) async throws -> GmailPage {
        GmailPage(conversations: mailbox == .inbox ? inbox : [], nextPageToken: mailbox == .inbox ? "page 2" : nil)
    }
    func conversation(id: String) async throws -> GmailConversation { throw GmailError.http(404) }
    func unreadInboxCount() async throws -> Int { 0 }
    func currentHistoryID() async throws -> String { "100" }
    func history(startHistoryID: String, pageToken: String?) async throws -> GmailHistoryPage {
        GmailHistoryPage(history: [], nextPageToken: nil, historyId: "100")
    }
    func metadata(id: String) async throws -> GmailConversation? { (inbox + unreadPages.flatMap(\.self)).first { $0.id == id } }
    func unreadThreads(in mailbox: Mailbox, excluding known: Set<String>, pageToken: String?) async throws -> GmailPage {
        unreadRequests.append(known)
        let index = pageToken.flatMap(Int.init) ?? 0
        return GmailPage(conversations: unreadPages[index].filter { !known.contains($0.id) },
                         nextPageToken: unreadPages.indices.contains(index + 1) ? String(index + 1) : nil)
    }
}

/// Lists a thread the caller already knows and a new one, and remembers what was asked for.
private actor UnreadListTransport: GmailTransport {
    private(set) var urls: [URL] = []

    func send(_ request: URLRequest) async throws -> GmailHTTPResponse {
        urls.append(request.url!)
        let object: [String: Any] = request.url!.path.hasSuffix("/threads")
            ? ["threads": [["id": "known"], ["id": "new"]], "nextPageToken": "next"]
            : ["id": "new", "messages": [["id": "m", "labelIds": ["INBOX", "UNREAD"], "snippet": "s", "internalDate": "1000",
                                          "payload": ["mimeType": "text/plain", "headers": [[String: String]]()]]]]
        return GmailHTTPResponse(data: try JSONSerialization.data(withJSONObject: object), statusCode: 200)
    }
}

@Suite("Unread filter", .timeLimit(.minutes(1)))
@MainActor
struct UnreadFilterTests {
    private func key(_ id: String, account: String = "a") -> ConversationKey {
        ConversationKey(accountID: account, threadID: id)
    }

    private func until(_ condition: () async -> Bool) async throws {
        while await !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    private func ids(_ hub: MailHub) -> [String] { hub.conversationKeys.map(\.threadID) }

    private func unread(_ id: String, at seconds: TimeInterval) -> GmailConversation {
        MailHubTests.conversation(id, at: seconds, unread: true)
    }

    /// Two read threads around an unread one.
    private func makeHub() async -> (HubAPI, MailHub) {
        let api = HubAPI([MailHubTests.conversation("new", at: 300), unread("fresh", at: 200), MailHubTests.conversation("old", at: 100)])
        return (api, await MailHubTests().makeHub(["a": api]))
    }

    // MARK: The list

    @Test("It leaves out read mail, and turning it off brings it back")
    func filtering() async {
        let (_, hub) = await makeHub()
        #expect(ids(hub) == ["new", "fresh", "old"])

        hub.showsOnlyUnread = true
        #expect(ids(hub) == ["fresh"])

        hub.showsOnlyUnread = false
        #expect(ids(hub) == ["new", "fresh", "old"])
    }

    @Test("A conversation that gets read stays while it is selected, then goes")
    func readWhileSelected() async {
        let (_, hub) = await makeHub()
        let model = InboxModel(hub: hub)
        hub.showsOnlyUnread = true
        model.select(key("fresh"))

        await hub.setUnread(key("fresh"), false)
        #expect(ids(hub) == ["fresh"])
        #expect(model.selectedID == key("fresh"))
        #expect(hub.list[key("fresh")]?.conversation.isUnread == false)

        model.select(nil)
        #expect(ids(hub).isEmpty)
    }

    @Test("A selected read conversation stays open when the filter is turned on")
    func turnedOnWithReadSelection() async {
        let (_, hub) = await makeHub()
        let model = InboxModel(hub: hub)
        model.select(key("new"))

        hub.showsOnlyUnread = true
        model.reconcileSelection()
        #expect(ids(hub) == ["new", "fresh"])
        #expect(model.selectedID == key("new"))

        model.select(key("fresh"))
        #expect(ids(hub) == ["fresh"])
    }

    @Test("A conversation marked as read without being selected goes right away, and marking it unread brings it back")
    func readWithoutSelecting() async {
        let (_, hub) = await makeHub()
        hub.showsOnlyUnread = true

        await hub.setUnread(key("fresh"), false)
        #expect(ids(hub).isEmpty)

        await hub.setUnread(key("fresh"), true)
        #expect(ids(hub) == ["fresh"])
    }

    @Test("In a Priority Inbox, the sections hold only unread mail")
    func priorityInbox() async {
        let (_, hub) = await makeHub()
        hub.usesPriorityInbox = true
        hub.showsOnlyUnread = true
        #expect(ids(hub) == ["fresh"])
        #expect(hub.list.sections.isEmpty)
    }

    // MARK: Where it applies

    @Test("Choosing another folder or account turns it off", arguments: [MailboxSelection.folder(.sent), .allInboxes])
    func turnsOff(selection: MailboxSelection) async {
        let hub = await MailHubTests().makeHub(["a": HubAPI([]), "b": HubAPI([])])
        hub.show(.folder(.inbox))
        hub.showsOnlyUnread = true

        hub.show(selection)
        #expect(!hub.showsOnlyUnread)

        hub.showsOnlyUnread = true
        hub.selectAccount("b")
        #expect(!hub.showsOnlyUnread)
    }

    @Test("Drafts and Outbox have nothing to filter", arguments: [Mailbox.drafts, .outbox])
    func notInDrafts(mailbox: Mailbox) async {
        let (_, hub) = await makeHub()
        hub.show(.folder(mailbox))
        hub.showsOnlyUnread = true
        #expect(!hub.canFilterUnread)
        #expect(!hub.filtersUnread)
    }

    @Test("Searching ignores it, and it is back when the search ends")
    func search() async {
        let (_, hub) = await makeHub()
        hub.showsOnlyUnread = true

        hub.setSearch("Subject", scope: .folder)
        await hub.performSearch()
        #expect(!hub.canFilterUnread)
        #expect(!hub.filtersUnread)
        #expect(ids(hub) == ["new", "fresh", "old"])

        hub.setSearch("", scope: .folder)
        #expect(hub.filtersUnread)
        #expect(ids(hub) == ["fresh"])
    }

    // MARK: Older unread mail

    @Test("Turning it on brings in older unread mail, and scrolling past a page of nothing new reaches the next one")
    func olderUnreadMail() async throws {
        let (api, hub) = await makeHub()
        await api.setUnreadPages([[unread("fresh", at: 200), unread("older", at: 50)], [unread("fresh", at: 200)], [unread("oldest", at: 10)]])

        hub.showsOnlyUnread = true
        try await until { hub.list[key("older")] != nil && !hub.isLoadingMailbox }
        #expect(ids(hub) == ["fresh", "older"])
        #expect(hub.hasMorePages)

        await hub.loadMore()
        #expect(ids(hub) == ["fresh", "older", "oldest"])
        #expect(!hub.hasMorePages)
        #expect(await api.unreadRequests.map(\.pageToken).suffix(2) == ["1", "2"])
    }

    @Test("Without the filter it doesn't ask, and turning it off stops asking")
    func onlyWhileFiltering() async throws {
        let (api, hub) = await makeHub()
        await hub.refresh()
        #expect(await api.unreadRequests.isEmpty)

        hub.showsOnlyUnread = true
        try await until { await !api.unreadRequests.isEmpty }
        try await until { !hub.isLoadingMailbox }
        hub.showsOnlyUnread = false
        let requests = await api.unreadRequests.count
        await hub.refresh()
        #expect(await api.unreadRequests.count == requests)
    }

    @Test("When Gmail can't be asked, the unread mail already loaded still shows")
    func askingFails() async throws {
        let (api, hub) = await makeHub()
        await api.failRequests(with: .http(500))
        hub.showsOnlyUnread = true
        await hub.refresh()
        #expect(ids(hub) == ["fresh"])
    }

    @Test("Older unread mail is saved with the folder, keeps its next page and isn't fetched again")
    func savedInTheCache() async throws {
        let cache = try await GmailCache.inMemory()
        let session = try await cache.session(for: CachedGmailAccount(id: "a", email: "a@example.com"))
        let api = SyncedUnreadAPI(inbox: [MailHubTests.conversation("new", at: 100)],
                                  unreadPages: [[unread("old", at: 50)], [unread("older", at: 10)]])
        let reader = GmailReaderStore(api: api, cache: session)
        reader.loadsUnreadThreads = true

        await reader.refresh()
        #expect(reader.mailboxError == nil)
        #expect(reader.conversations.map(\.id).sorted() == ["new", "old"])
        #expect(reader.nextPageToken == "page 2")
        #expect(reader.nextUnreadPageToken == "1")

        await reader.loadMoreUnread()
        #expect(reader.mailboxError == nil)
        #expect(reader.conversations.map(\.id).sorted() == ["new", "old", "older"])
        #expect(reader.nextPageToken == "page 2")
        #expect(reader.nextUnreadPageToken == nil)

        await reader.refresh()
        #expect(reader.conversations.map(\.id).sorted() == ["new", "old", "older"])
        #expect(await api.unreadRequests.last == ["new", "old", "older"])

        let saved = try await session.loadMailbox(.inbox)
        #expect(saved?.conversations.map(\.id).sorted() == ["new", "old", "older"])
    }

    @Test("Gmail is asked for the folder's unread threads, and threads already known aren't read again")
    func request() async throws {
        let transport = UnreadListTransport()
        let api = GmailAPI(transport: transport) { "fixture-token" }

        let page = try await api.unreadThreads(in: .inbox, excluding: ["known"], pageToken: "token")
        #expect(page.conversations.map(\.id) == ["new"])
        #expect(page.nextPageToken == "next")

        let urls = await transport.urls
        let list = try #require(urls.first { $0.path.hasSuffix("/threads") })
        let query = try #require(URLComponents(url: list, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "labelIds", value: "INBOX")))
        #expect(query.contains(URLQueryItem(name: "q", value: "is:unread")))
        #expect(query.contains(URLQueryItem(name: "pageToken", value: "token")))
        #expect(!urls.contains { $0.path.hasSuffix("/known") })
    }
}
