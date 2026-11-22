import AppKit
import SwiftUI
import Testing
@testable import Postie

@Suite("Reading pane layout", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ReadingPaneLayoutTests {
    @Test("Without a split, opening a conversation replaces the list, and Esc brings the list back")
    func noSplit() async throws {
        let window = try await Window(layout: .noSplit)
        defer { window.close() }
        let table = try await window.waitForList()

        window.open(row: 0, in: table)
        try await window.waitUntil { window.list == nil && window.hub.openConversation(for: window.firstKey) != nil }

        window.pressEscape()
        try await window.waitUntil { window.list != nil }
    }

    @Test("Split horizontally or vertically, the list stays while a conversation is open")
    func splits() async throws {
        for layout in [ReadingPaneLayout.horizontal, .vertical] {
            let window = try await Window(layout: layout)
            defer { window.close() }
            let table = try await window.waitForList()

            window.open(row: 0, in: table)
            try await window.waitUntil { window.hub.openConversation(for: window.firstKey) != nil }
            #expect(window.list != nil)
        }
    }

    @Test("Changing the layout takes effect in the open window")
    func switchesLive() async throws {
        let window = try await Window(layout: .vertical)
        defer { window.close() }
        let table = try await window.waitForList()
        window.open(row: 0, in: table)
        try await window.waitUntil { window.hub.openConversation(for: window.firstKey) != nil }

        window.preferences.set(ReadingPaneLayout.noSplit.rawValue, forKey: SettingsKey.readingPaneLayout)
        try await window.waitUntil { window.list == nil }

        window.preferences.set(ReadingPaneLayout.horizontal.rawValue, forKey: SettingsKey.readingPaneLayout)
        try await window.waitUntil { window.list != nil }
    }

    @MainActor
    private final class Window {
        let hub: MailHub
        let preferences: UserDefaults
        private let suiteName = "ReadingPaneLayoutTests.\(UUID().uuidString)"
        private let window: NSWindow
        private let host: NSView

        init(layout: ReadingPaneLayout) async throws {
            hub = try await SelectionRegressionMail().makeHub()
            preferences = try #require(UserDefaults(suiteName: suiteName))
            preferences.set(layout.rawValue, forKey: SettingsKey.readingPaneLayout)
            host = NSHostingView(rootView: GmailInboxView(hub: hub).defaultAppStorage(preferences))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
        }

        var firstKey: ConversationKey? { hub.conversationKeys.first }

        /// The conversation list, not the sidebar's folders, which has more rows than the two conversations.
        var list: NSTableView? {
            let count = hub.conversationKeys.count
            return find(NSTableView.self, in: host) { $0.numberOfRows == count && count > 0 }
        }

        func waitForList() async throws -> NSTableView {
            try await waitUntil { !hub.showingCachedMail && !hub.isLoadingMailbox && list != nil }
            return try #require(list)
        }

        func open(row: Int, in table: NSTableView) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if let outline = table as? NSOutlineView {
                outline.delegate?.outlineViewSelectionDidChange?(Notification(name: NSOutlineView.selectionDidChangeNotification, object: outline))
            }
        }

        func pressEscape() {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                         charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)
            if let event { window.performKeyEquivalent(with: event) }
        }

        func waitUntil(_ ready: () -> Bool) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while clock.now < deadline {
                host.layoutSubtreeIfNeeded()
                if ready() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            throw Timeout()
        }

        func close() {
            window.close()
            preferences.removePersistentDomain(forName: suiteName)
        }

        private func find<T: NSView>(_ type: T.Type, in view: NSView, where matches: (T) -> Bool) -> T? {
            if let view = view as? T, !view.isHiddenOrHasHiddenAncestor, matches(view) { return view }
            for subview in view.subviews {
                if let found = find(type, in: subview, where: matches) { return found }
            }
            return nil
        }

        private struct Timeout: Error {}
    }
}
