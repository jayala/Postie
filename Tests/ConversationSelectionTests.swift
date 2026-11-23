import Foundation
import Testing
@testable import Postie

@Suite("Conversation selection policy")
@MainActor
struct ConversationSelectionTests {
    @Test("Navigation uses the visible order without wrapping", arguments: [
        ("middle", -1, ["new", "middle", "old"], "new"),
        ("middle", 1, ["old", "middle", "new"], "new"),
        ("new", -1, ["new", "old"], nil),
        ("old", 1, ["new", "old"], nil),
        ("missing", 1, ["new", "old"], nil),
        ("new", 1, [], nil)
    ])
    func navigation(example: (String, Int, [String], String?)) {
        var selection = ConversationSelection<String>()
        selection.select(example.0)
        #expect(selection.neighbor(offset: example.1, visibleIDs: example.2) == example.3)
    }

    @Test("With several conversations selected there is no previous or next one")
    func navigationWithSeveralSelected() {
        var selection = ConversationSelection<String>()
        selection.select(["new", "middle"])
        #expect(selection.neighbor(offset: -1, visibleIDs: ["new", "middle", "old"]) == nil)
        #expect(selection.neighbor(offset: 1, visibleIDs: ["new", "middle", "old"]) == nil)
    }

    @Test("Loading a list opens nothing until the user picks a conversation")
    func nothingOpensByItself() {
        var selection = ConversationSelection<String>()
        selection.updateFromList([], visibleIDs: [])
        selection.reconcile(with: [])
        selection.reconcile(with: ["open", "older"])
        #expect(selection.selectedID == nil)
        selection.updateFromList(["open"], visibleIDs: ["open", "older"])
        #expect(selection.selectedID == "open")
    }

    @Test("Replacing cached rows and inserting newer mail preserves conversation identity")
    func insertion() {
        var selection = ConversationSelection<String>()
        selection.select("open")
        selection.reconcile(with: ["open", "older"])
        selection.reconcile(with: ["new", "open", "older"])
        #expect(selection.selectedID == "open")
    }

    @Test("Archive selects the next older identity, not the row at the old position")
    func archiveAfterInsertion() throws {
        var selection = ConversationSelection<String>()
        selection.select("open")
        let tokenRequest = selection.beginRemoval(of: "open", visibleIDs: ["new", "open", "older"])
        let token = try #require(tokenRequest)
        // Another insertion and a reorder happen while the archive request is in flight.
        selection.finishRemoval(token, removed: true, visibleIDs: ["newer", "older", "new"])
        #expect(selection.selectedID == "older")
    }

    @Test("Without opening the next one, removing the open conversation leaves nothing selected")
    func removalReturnsToList() throws {
        var selection = ConversationSelection<String>()
        selection.select("open")
        let tokenRequest = selection.beginRemoval(of: ["open"], visibleIDs: ["new", "open", "older"], opensNext: false)
        let token = try #require(tokenRequest)
        selection.rowRemoved(token, visibleIDs: ["new", "older"])
        #expect(selection.selectedIDs.isEmpty)
    }

    @Test("Vanished neighbors are skipped; newer mail is the fallback")
    func missingNeighbors() throws {
        var selection = ConversationSelection<String>()
        selection.select("open")
        let tokenRequest = selection.beginRemoval(of: "open", visibleIDs: ["new", "open", "older", "oldest"])
        let token = try #require(tokenRequest)
        selection.finishRemoval(token, removed: true, visibleIDs: ["arrived", "new", "oldest"])
        #expect(selection.selectedID == "oldest")
        selection.select("oldest")
        let lastRequest = selection.beginRemoval(of: "oldest", visibleIDs: ["arrived", "new", "oldest"])
        let last = try #require(lastRequest)
        selection.finishRemoval(last, removed: true, visibleIDs: ["arrived", "new"])
        #expect(selection.selectedID == "new")
    }

    @Test("Background disappearance clears selection instead of opening the first row")
    func externalRemoval() {
        var selection = ConversationSelection<String>()
        selection.select("open")
        selection.reconcile(with: ["new", "older"])
        #expect(selection.selectedID == nil)
        selection.reconcile(with: ["newest", "new", "older"])
        #expect(selection.selectedID == nil)
    }

    @Test("Archiving the last conversation clears selection, even after another arrival")
    func emptyInbox() throws {
        var selection = ConversationSelection<String>()
        selection.select("open")
        let tokenRequest = selection.beginRemoval(of: "open", visibleIDs: ["open"])
        let token = try #require(tokenRequest)
        selection.finishRemoval(token, removed: true, visibleIDs: [])
        #expect(selection.selectedID == nil)
        selection.reconcile(with: ["new"])
        #expect(selection.selectedID == nil)
    }

    @Test("Rejected removal keeps selection and permits retry")
    func failure() throws {
        var selection = ConversationSelection<String>()
        selection.select("open")
        let tokenRequest = selection.beginRemoval(of: "open", visibleIDs: ["open", "older"])
        let token = try #require(tokenRequest)
        let duplicate = selection.beginRemoval(of: "open", visibleIDs: ["open", "older"])
        #expect(duplicate == nil)
        selection.finishRemoval(token, removed: false, visibleIDs: ["open", "older"])
        #expect(selection.selectedID == "open")
        #expect(!selection.isRemoving("open"))
        let retry = selection.beginRemoval(of: "open", visibleIDs: ["open", "older"])
        #expect(retry != nil)
    }

    @Test("Changing selection during archive wins, even when returning to the same thread")
    func userSelectionWins() throws {
        var selection = ConversationSelection<String>()
        selection.select("open")
        let tokenRequest = selection.beginRemoval(of: "open", visibleIDs: ["open", "other", "older"])
        let token = try #require(tokenRequest)
        selection.select("other")
        selection.select("open")
        selection.finishRemoval(token, removed: true, visibleIDs: ["other", "older"])
        selection.reconcile(with: ["other", "older"])
        #expect(selection.selectedID == nil)
    }

    @Test("Removing an unselected row and overlapping operations preserve the open thread")
    func overlappingRemovals() throws {
        var selection = ConversationSelection<String>()
        selection.select("open")
        let otherRequest = selection.beginRemoval(of: "other", visibleIDs: ["other", "open", "older"])
        let other = try #require(otherRequest)
        let openRequest = selection.beginRemoval(of: "open", visibleIDs: ["other", "open", "older"])
        let open = try #require(openRequest)
        selection.finishRemoval(other, removed: true, visibleIDs: ["open", "older"])
        #expect(selection.selectedID == "open")
        #expect(selection.isRemoving("open"))
        selection.finishRemoval(open, removed: true, visibleIDs: ["older"])
        #expect(selection.selectedID == "older")
    }

    @Test("List deselection on removal applies the same neighbor policy")
    func listDeselectsRemovedRow() throws {
        var selection = ConversationSelection<String>()
        selection.select("open")
        let tokenRequest = selection.beginRemoval(of: "open", visibleIDs: ["new", "open", "older"])
        let token = try #require(tokenRequest)
        selection.updateFromList([], visibleIDs: ["new", "older"])
        #expect(selection.selectedID == "older")
        selection.finishRemoval(token, removed: true, visibleIDs: ["new", "older"])
        #expect(selection.selectedID == "older")
    }

    @Test("Folder reset clears selection, invalidates pending removals and opens nothing")
    func folderChange() throws {
        var selection = ConversationSelection<String>()
        selection.select("open")
        let tokenRequest = selection.beginRemoval(of: "open", visibleIDs: ["open", "older"])
        let token = try #require(tokenRequest)
        selection.reset()
        #expect(selection.selectedID == nil)
        selection.reconcile(with: [])
        selection.reconcile(with: ["sent"])
        #expect(selection.selectedID == nil)
        selection.select("sent")
        let applied = selection.finishRemoval(token, removed: true, visibleIDs: ["sent"])
        #expect(!applied)
        #expect(selection.selectedID == "sent")
    }

    @Test("Several selected conversations open nothing; narrowing back to one opens it")
    func severalSelected() {
        var selection = ConversationSelection<String>()
        selection.updateFromList(["a"], visibleIDs: ["a", "b", "c"])
        #expect(selection.selectedID == "a")
        selection.updateFromList(["a", "b"], visibleIDs: ["a", "b", "c"])
        #expect(selection.selectedIDs == ["a", "b"])
        #expect(selection.selectedID == nil)
        selection.updateFromList(["b"], visibleIDs: ["a", "b", "c"])
        #expect(selection.selectedID == "b")
    }

    @Test("Removing a selection never opens its last row, then moves past the oldest selected")
    func removingSeveral() throws {
        var selection = ConversationSelection<String>()
        selection.select(["b", "c"])
        let tokenRequest = selection.beginRemoval(of: Set(["b", "c"]), visibleIDs: ["a", "b", "c", "d"])
        let token = try #require(tokenRequest)
        #expect(selection.isRemoving("b") && selection.isRemoving("c"))

        // One row has gone: the other must not become the open conversation.
        let finishedEarly = selection.rowRemoved(token, visibleIDs: ["a", "c", "d"])
        #expect(!finishedEarly)
        selection.reconcile(with: ["a", "c", "d"])
        selection.updateFromList(["c"], visibleIDs: ["a", "c", "d"])
        #expect(selection.selectedID == nil)
        #expect(selection.selectedIDs == ["b", "c"])

        let finished = selection.rowRemoved(token, visibleIDs: ["a", "d"])
        #expect(finished)
        #expect(selection.selectedID == "d")
        #expect(!selection.isRemoving("c"))
    }

    @Test("Removing a selection that ends the list falls back to the nearest newer unselected row")
    func removingSeveralAtTheEnd() throws {
        var selection = ConversationSelection<String>()
        selection.select(["b", "d"])
        let tokenRequest = selection.beginRemoval(of: Set(["b", "d"]), visibleIDs: ["a", "b", "c", "d"])
        let token = try #require(tokenRequest)
        selection.finishRemoval(token, removed: true, visibleIDs: ["a", "c"])
        #expect(selection.selectedID == "c")
    }

    @Test("Rows Gmail refused stay selected; those that went are dropped")
    func partlyRefused() throws {
        var selection = ConversationSelection<String>()
        selection.select(["a", "b", "c"])
        let tokenRequest = selection.beginRemoval(of: Set(["a", "b", "c"]), visibleIDs: ["a", "b", "c", "d"])
        let token = try #require(tokenRequest)
        selection.finishRemoval(token, removed: true, visibleIDs: ["b", "c", "d"])
        #expect(selection.selectedIDs == ["b", "c"])
        #expect(!selection.isRemoving("b"))
    }

    @Test("Refusing every row keeps the whole selection")
    func allRefused() throws {
        var selection = ConversationSelection<String>()
        selection.select(["a", "b"])
        let tokenRequest = selection.beginRemoval(of: Set(["a", "b"]), visibleIDs: ["a", "b", "c"])
        let token = try #require(tokenRequest)
        selection.finishRemoval(token, removed: false, visibleIDs: ["a", "b", "c"])
        #expect(selection.selectedIDs == ["a", "b"])
    }

    @Test("Changing the selection during a bulk removal wins")
    func userSelectionWinsOverBulkRemoval() throws {
        var selection = ConversationSelection<String>()
        selection.select(["a", "b"])
        let tokenRequest = selection.beginRemoval(of: Set(["a", "b"]), visibleIDs: ["a", "b", "c", "d"])
        let token = try #require(tokenRequest)
        selection.updateFromList(["c"], visibleIDs: ["b", "c", "d"])
        let applied = selection.rowRemoved(token, visibleIDs: ["c", "d"])
        #expect(!applied)
        #expect(selection.selectedID == "c")
    }

    @Test("Removing one row of a selection, or a row outside it, keeps the rest")
    func removingOneOfSeveral() throws {
        var selection = ConversationSelection<String>()
        selection.select(["a", "b", "c"])
        let outsideRequest = selection.beginRemoval(of: "d", visibleIDs: ["a", "b", "c", "d"])
        let outside = try #require(outsideRequest)
        selection.finishRemoval(outside, removed: true, visibleIDs: ["a", "b", "c"])
        #expect(selection.selectedIDs == ["a", "b", "c"])

        let insideRequest = selection.beginRemoval(of: "b", visibleIDs: ["a", "b", "c"])
        let inside = try #require(insideRequest)
        selection.reconcile(with: ["a", "c"])
        selection.finishRemoval(inside, removed: true, visibleIDs: ["a", "c"])
        #expect(selection.selectedIDs == ["a", "c"])
    }

    @Test("A selected row vanishing in the background only drops that row")
    func severalWithExternalRemoval() {
        var selection = ConversationSelection<String>()
        selection.select(["a", "b", "c"])
        selection.reconcile(with: ["a", "c", "d"])
        #expect(selection.selectedIDs == ["a", "c"])
    }

    @Test("Account identity disambiguates equal Gmail thread IDs")
    func accounts() throws {
        let a = ConversationKey(accountID: "a", threadID: "same")
        let b = ConversationKey(accountID: "b", threadID: "same")
        var selection = ConversationSelection<ConversationKey>()
        selection.select(a)
        let tokenRequest = selection.beginRemoval(of: a, visibleIDs: [a, b])
        let token = try #require(tokenRequest)
        selection.finishRemoval(token, removed: true, visibleIDs: [b])
        #expect(selection.selectedID == b)
    }

    @Test("Checking a conversation's box opens nothing, even when it is the only one checked")
    func checkingOpensNothing() {
        var selection = ConversationSelection<String>()
        selection.select("open")
        #expect(selection.markedIDs.isEmpty)
        selection.toggleMark("b")
        #expect(selection.selectedIDs == ["b"])
        #expect(selection.selectedID == nil)
        selection.toggleMark("c")
        #expect(selection.markedIDs == ["b", "c"])
        selection.toggleMark("b")
        #expect(selection.markedIDs == ["c"])
        #expect(selection.selectedID == nil)
        selection.toggleMark("c")
        #expect(selection.selectedIDs.isEmpty)
        #expect(!selection.isMarking)
    }

    @Test("Shift-clicking a checkbox checks everything from the last one clicked")
    func shiftCheckRange() {
        let visible = ["a", "b", "c", "d", "e", "f"]
        var selection = ConversationSelection<String>()
        selection.toggleMark("b")
        selection.extendMark(to: "e", visibleIDs: visible)
        #expect(selection.markedIDs == ["b", "c", "d", "e"])
        // Upwards from the new anchor, and unchecking takes the clicked box's new state.
        selection.extendMark(to: "d", visibleIDs: visible)
        #expect(selection.markedIDs == ["b", "c"])
        selection.extendMark(to: "a", visibleIDs: visible)
        #expect(selection.markedIDs == ["a", "b", "c", "d"])
    }

    @Test("Shift-clicking a checkbox after opening a conversation checks from that one")
    func shiftCheckFromOpenConversation() {
        var selection = ConversationSelection<String>()
        selection.updateFromList(["b"], visibleIDs: ["a", "b", "c", "d"])
        selection.extendMark(to: "d", visibleIDs: ["a", "b", "c", "d"])
        #expect(selection.markedIDs == ["b", "c", "d"])
        #expect(selection.selectedID == nil)
    }

    @Test("Clicking the row of the only checked conversation opens it")
    func clickingCheckedRowOpensIt() {
        var selection = ConversationSelection<String>()
        selection.toggleMark("b")
        selection.updateFromList(["b"], visibleIDs: ["a", "b"])
        #expect(selection.selectedID == "b")
        #expect(selection.markedIDs.isEmpty)
    }

    @Test("Checked conversations that go away stay checked without opening the last one")
    func backgroundRemovalKeepsMarking() {
        var selection = ConversationSelection<String>()
        selection.mark(["a", "b"])
        selection.reconcile(with: ["b", "c"])
        #expect(selection.markedIDs == ["b"])
        #expect(selection.selectedID == nil)
    }

    @Test("Archiving checked conversations opens nothing")
    func archivingCheckedOpensNothing() throws {
        var selection = ConversationSelection<String>()
        selection.mark(["a", "b"])
        let tokenRequest = selection.beginRemoval(of: ["a", "b"], visibleIDs: ["a", "b", "c"], opensNext: false)
        let token = try #require(tokenRequest)
        selection.finishRemoval(token, removed: true, visibleIDs: ["c"])
        #expect(selection.selectedIDs.isEmpty)
        #expect(!selection.isMarking)
    }
}
