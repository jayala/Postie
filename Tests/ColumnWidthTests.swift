import Foundation
import Testing
@testable import Postie

@Suite("Column widths")
@MainActor
struct ColumnWidthTests {
    private func makeHub(_ preferences: UserDefaults?) -> MailHub {
        MailHub(accounts: AccountStore(vault: MemoryAccountVault()), persistsMail: false, syncsInBackground: false, preferences: preferences)
    }

    private func makePreferences() -> UserDefaults {
        UserDefaults(suiteName: "postie-tests-\(UUID().uuidString)")!
    }

    @Test("Columns start at their default widths")
    func defaults() {
        let hub = makeHub(makePreferences())
        #expect(hub.columnWidth(.sidebar) == MailColumn.sidebar.defaultWidth)
        #expect(hub.columnWidth(.list) == MailColumn.list.defaultWidth)
    }

    @Test("A dragged width is still there after reopening")
    func remembersWidths() {
        let preferences = makePreferences()
        makeHub(preferences).setColumnWidth(401, for: .list)

        let reopened = makeHub(preferences)
        #expect(reopened.columnWidth(.list) == 401)
        #expect(reopened.columnWidth(.sidebar) == MailColumn.sidebar.defaultWidth)
    }

    @Test("Resetting a column forgets its width and leaves the other one alone")
    func resetsOneColumn() {
        let preferences = makePreferences()
        let hub = makeHub(preferences)
        hub.setColumnWidth(240, for: .sidebar)
        hub.setColumnWidth(401, for: .list)

        hub.setColumnWidth(nil, for: .sidebar)

        #expect(hub.columnWidth(.sidebar) == MailColumn.sidebar.defaultWidth)
        #expect(hub.columnWidth(.list) == 401)
        #expect(preferences.object(forKey: SettingsKey.sidebarWidth) == nil)
        #expect(makeHub(preferences).columnWidth(.sidebar) == MailColumn.sidebar.defaultWidth)
    }

    @Test("A saved width outside what the column allows is brought within it")
    func clampsSavedWidths() {
        let preferences = makePreferences()
        preferences.set(5000.0, forKey: SettingsKey.conversationListWidth)
        preferences.set(10.0, forKey: SettingsKey.sidebarWidth)

        let hub = makeHub(preferences)
        #expect(hub.columnWidth(.list) == MailColumn.list.widthRange.upperBound)
        #expect(hub.columnWidth(.sidebar) == MailColumn.sidebar.widthRange.lowerBound)
    }

    @Test("Without preferences a width lasts until quitting")
    func withoutPreferences() {
        let hub = makeHub(nil)
        hub.setColumnWidth(401, for: .list)
        #expect(hub.columnWidth(.list) == 401)
        #expect(makeHub(nil).columnWidth(.list) == MailColumn.list.defaultWidth)
    }
}
