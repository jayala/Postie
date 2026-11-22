import SwiftUI

/// Where the open conversation goes in relation to the conversation list, as Gmail's split options.
enum ReadingPaneLayout: String, CaseIterable, Identifiable {
    /// The list fills the window, and opening a conversation replaces it until you go back.
    case noSplit
    /// The conversation is to the right of the list.
    case vertical
    /// The conversation is below the list.
    case horizontal

    static let defaultLayout = ReadingPaneLayout.vertical

    var id: Self { self }

    var title: String {
        switch self {
        case .noSplit: String(localized: "No Split")
        case .vertical: String(localized: "Vertical Split")
        case .horizontal: String(localized: "Horizontal Split")
        }
    }

    var symbol: String {
        switch self {
        case .noSplit: "rectangle"
        case .vertical: "rectangle.split.2x1"
        case .horizontal: "rectangle.split.1x2"
        }
    }
}

/// Picks the reading pane layout. The icon shows the current one, as in Gmail.
struct ReadingPaneLayoutMenu: View {
    @AppStorage(SettingsKey.readingPaneLayout) private var layout = ReadingPaneLayout.defaultLayout

    var body: some View {
        Menu {
            ReadingPaneLayoutPicker(layout: $layout)
        } label: {
            Label("Reading Pane", systemImage: layout.symbol)
        }
        .menuIndicator(.hidden)
        .help("Reading Pane: \(layout.title)")
    }
}

/// The layouts as a checkmarked list, for the toolbar menu and the View menu.
struct ReadingPaneLayoutPicker: View {
    @Binding var layout: ReadingPaneLayout

    var body: some View {
        Picker("Reading Pane", selection: $layout) {
            ForEach(ReadingPaneLayout.allCases) { layout in
                Label(layout.title, systemImage: layout.symbol).tag(layout)
            }
        }
        .pickerStyle(.inline)
    }
}
