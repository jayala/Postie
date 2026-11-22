import AppKit
import SwiftUI

/// The columns whose width can be dragged, in the order they appear. The conversation takes what is left.
enum MailColumn: CaseIterable {
    case sidebar
    case list

    var widthRange: ClosedRange<CGFloat> {
        switch self {
        case .sidebar: 180...260
        case .list: 280...440
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .sidebar: 200
        case .list: 330
        }
    }

    var settingsKey: String {
        switch self {
        case .sidebar: SettingsKey.sidebarWidth
        case .list: SettingsKey.conversationListWidth
        }
    }
}

/// Remembers the widths the columns are dragged to, and puts a column back to its default when its divider is
/// double-clicked. `NavigationSplitView` can neither report nor set widths, so this goes to the `NSSplitView` behind it.
/// Put it in a column, as it finds the split view among its ancestors. `columns` are the split view's leading
/// columns, in order: without a list column, only the sidebar's width is kept.
struct ColumnWidthKeeper: NSViewRepresentable {
    let hub: MailHub
    var columns: [MailColumn] = MailColumn.allCases

    func makeNSView(context: Context) -> NSView { KeeperView(hub: hub, columns: columns) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class KeeperView: NSView {
        let hub: MailHub
        let columns: [MailColumn]
        private weak var splitView: NSSplitView?
        private var mouseDownMonitor: Any?

        init(hub: MailHub, columns: [MailColumn]) {
            self.hub = hub
            self.columns = columns
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
            mouseDownMonitor = nil
            guard let window else { return }
            var ancestor = superview
            while let view = ancestor, !(view is NSSplitView) { ancestor = view.superview }
            splitView = ancestor as? NSSplitView
            mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self else { return event }
                return self.handleMouseDown(event)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(restoreWidths), name: NSWindow.didResizeNotification, object: window)
            // Not right away: with frames NSSplitView saved by itself, the list first opens at its minimum width.
            DispatchQueue.main.async { [weak self] in self?.restoreWidths() }
        }

        /// A window too narrow for them squeezes the columns, which get their widths back as soon as it has room again.
        @objc private func restoreWidths() {
            guard let splitView else { return }
            for (index, column) in columns.enumerated()
            where index < splitView.arrangedSubviews.count - 1 && !splitView.isSubviewCollapsed(splitView.arrangedSubviews[index]) {
                splitView.setPosition(trailingEdge(of: index - 1) + hub.columnWidth(column), ofDividerAt: index)
            }
        }

        private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
            guard let divider = divider(under: event) else { return event }
            if event.clickCount == 2 {
                hub.setColumnWidth(nil, for: columns[divider])
                restoreWidths()
                return nil
            }
            // The split view follows the drag in a loop of its own, and the run loop gets back to its default mode when it ends.
            let widthsBefore = widths
            RunLoop.main.perform(inModes: [.default]) { [weak self] in
                MainActor.assumeIsolated { self?.saveWidths(changedFrom: widthsBefore) }
            }
            return event
        }

        /// The divider a click landed on, if any.
        private func divider(under event: NSEvent) -> Int? {
            guard let splitView, let window, event.window === window,
                  let hit = window.contentView?.superview?.hitTest(event.locationInWindow), hit === splitView else { return nil }
            let x = splitView.convert(event.locationInWindow, from: nil).x
            return columns.indices.min { abs(trailingEdge(of: $0) - x) < abs(trailingEdge(of: $1) - x) }
        }

        private func trailingEdge(of index: Int) -> CGFloat {
            guard let splitView, index >= 0, index < splitView.arrangedSubviews.count else { return 0 }
            let view = splitView.arrangedSubviews[index]
            return splitView.isSubviewCollapsed(view) ? 0 : view.frame.maxX
        }

        /// How much of each column can be seen. A column reaches under the glass sidebar, so its frame says nothing about that.
        private var widths: [CGFloat] {
            columns.indices.map { trailingEdge(of: $0) - trailingEdge(of: $0 - 1) }
        }

        private func saveWidths(changedFrom previous: [CGFloat]) {
            for (index, (column, width)) in zip(columns, widths).enumerated()
            where width != previous[index] && width > 0 {
                hub.setColumnWidth(width, for: column)
            }
        }
    }
}
