import Foundation

/// Selection belongs to conversations, never to row positions.
struct ConversationSelection<ID: Hashable> {
    private(set) var selectedIDs: Set<ID> = []
    /// Distinguishes separate openings, even when selection leaves and returns to the same ID.
    private(set) var revision = 0
    /// Conversations checked with their checkboxes, like Gmail: none of them opens, even when only one is checked.
    private(set) var isMarking = false
    /// Where a Shift-click on a checkbox extends from: the last one checked, or the conversation opened last.
    private(set) var anchor: ID?
    private var removals: [UUID: Removal] = [:]

    private struct Removal {
        let ids: Set<ID>
        let revision: Int
        // In the visible order at action time: older neighbors first, then newer ones.
        let neighbors: [ID]
    }

    /// The conversation to open. Several selected conversations stay closed.
    var selectedID: ID? { !isMarking && selectedIDs.count == 1 ? selectedIDs.first : nil }

    mutating func select(_ id: ID?) {
        select(id.map { [$0] } ?? [])
    }

    mutating func select(_ ids: Set<ID>) {
        guard selectedIDs != ids || isMarking else { return }
        selectedIDs = ids
        isMarking = false
        if ids.count == 1 { anchor = ids.first } else if ids.isEmpty { anchor = nil }
        revision += 1
    }

    /// The checkboxes that show as checked. An open conversation is selected but not checked.
    var markedIDs: Set<ID> { isMarking || selectedIDs.count > 1 ? selectedIDs : [] }

    /// Checks or unchecks one conversation's checkbox. Checking one closes the open conversation, as it isn't checked.
    mutating func toggleMark(_ id: ID) {
        mark(markedIDs.symmetricDifference([id]), anchor: id)
    }

    /// Shift-click on a checkbox: everything from the anchor to `id`, in the visible order, takes the state
    /// the clicked checkbox is changing to. Without an anchor in the list, it only toggles `id`.
    mutating func extendMark(to id: ID, visibleIDs: [ID]) {
        guard let anchor, anchor != id, let start = visibleIDs.firstIndex(of: anchor),
              let end = visibleIDs.firstIndex(of: id) else {
            toggleMark(id)
            return
        }
        let range = Set(visibleIDs[min(start, end)...max(start, end)])
        let marked = markedIDs
        mark(marked.contains(id) ? marked.subtracting(range) : marked.union(range), anchor: id)
    }

    /// Checks these conversations, and only these, without opening any.
    mutating func mark(_ ids: Set<ID>, anchor: ID? = nil) {
        guard !ids.isEmpty else {
            select(nil)
            return
        }
        guard selectedIDs != ids || !isMarking else {
            self.anchor = anchor ?? self.anchor
            return
        }
        selectedIDs = ids
        isMarking = true
        self.anchor = anchor ?? self.anchor
        revision += 1
    }

    /// A new folder starts with nothing open, until the user picks a conversation.
    mutating func reset() {
        select(nil)
        removals = [:]
    }

    mutating func reconcile(with visibleIDs: [ID]) {
        let visible = Set(visibleIDs)
        let missing = selectedIDs.subtracting(visible)
        guard !missing.isEmpty else { return }
        if let removal = removals.values.first(where: { $0.ids == selectedIDs && $0.revision == revision }) {
            // The whole selection is going. Wait for all of it, so that the last row left never opens by itself.
            guard selectedIDs.isDisjoint(with: visible) else { return }
            select(removal.neighbors.first { visible.contains($0) })
        } else {
            // Background disappearance only drops those rows; only an explicit removal advances selection.
            let remaining = selectedIDs.subtracting(missing)
            if isMarking { mark(remaining) } else { select(remaining) }
        }
    }

    /// List may emit a smaller selection as selected rows disappear. Apply our policy, not its row fallback.
    mutating func updateFromList(_ ids: Set<ID>, visibleIDs: [ID]) {
        let visible = Set(visibleIDs)
        let stillVisible = selectedIDs.intersection(visible)
        if ids == stillVisible, stillVisible != selectedIDs {
            reconcile(with: visibleIDs)
        } else if isMarking, ids == selectedIDs, ids.count == 1 {
            // Clicking the only checked conversation's row opens it.
            select(ids)
        } else if ids != selectedIDs, ids.isEmpty || !ids.isDisjoint(with: visible) {
            select(ids.intersection(visible))
        }
    }

    /// Navigation follows the current visible order and never wraps or opens an arbitrary row.
    func neighbor(offset: Int, visibleIDs: [ID]) -> ID? {
        guard let selectedID, let index = visibleIDs.firstIndex(of: selectedID),
              visibleIDs.indices.contains(index + offset) else { return nil }
        return visibleIDs[index + offset]
    }

    func isRemoving(_ id: ID) -> Bool { removals.values.contains { $0.ids.contains(id) } }

    mutating func beginRemoval(of id: ID, visibleIDs: [ID]) -> UUID? {
        beginRemoval(of: [id], visibleIDs: visibleIDs)
    }

    /// Each operation owns its snapshot; another removal cannot overwrite or clear it.
    /// Without `opensNext`, nothing is selected once the rows are gone, and the list is back on its own.
    mutating func beginRemoval(of ids: Set<ID>, visibleIDs: [ID], opensNext: Bool = true) -> UUID? {
        guard ids.allSatisfy({ !isRemoving($0) && visibleIDs.contains($0) }),
              let last = visibleIDs.lastIndex(where: { ids.contains($0) }) else { return nil }
        let token = UUID()
        let neighbors = opensNext
            ? (Array(visibleIDs.dropFirst(last + 1)) + visibleIDs.prefix(last).reversed()).filter { !ids.contains($0) }
            : []
        removals[token] = Removal(ids: ids, revision: revision, neighbors: neighbors)
        return token
    }

    /// Called as each row is removed, before the follow-up refresh can reorder the list. The last row finishes the removal.
    @discardableResult
    mutating func rowRemoved(_ token: UUID, visibleIDs: [ID]) -> Bool {
        guard let removal = removals[token], removal.ids.isDisjoint(with: visibleIDs) else { return false }
        return finishRemoval(token, removed: true, visibleIDs: visibleIDs)
    }

    /// A failed/stale operation only releases its token. User selection changes always win.
    /// Rows Gmail refused stay selected; once none are left, selection moves to the next neighbor.
    @discardableResult
    mutating func finishRemoval(_ token: UUID, removed: Bool, visibleIDs: [ID]) -> Bool {
        guard let removal = removals.removeValue(forKey: token) else { return false }
        guard removed, selectedIDs == removal.ids, revision == removal.revision else { return false }
        let refused = removal.ids.intersection(visibleIDs)
        if refused.isEmpty { select(removal.neighbors.first { visibleIDs.contains($0) }) }
        else if isMarking { mark(refused) }
        else { select(refused) }
        return true
    }
}
