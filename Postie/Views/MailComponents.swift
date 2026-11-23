import SwiftUI

struct SenderAvatar: View {
    let message: MailMessage
    var size: CGFloat = 36

    var body: some View {
        Text(message.initials)
            .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary, in: Circle())
            .accessibilityHidden(true)
    }
}

/// A conversation row's checkbox, for checking several conversations without opening them.
struct RowCheckbox {
    var isMarked: Bool
    /// Shown without the pointer over the row, while any conversation is checked.
    var isAlwaysVisible: Bool
    /// Called with whether Shift was held.
    var toggle: (_ extending: Bool) -> Void
}

struct MailThreadRow: View {
    let thread: MailThread
    var isPending = false
    var textSize = ConversationListTextSize.defaultSize
    var checkbox: RowCheckbox?
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // .increased while the row sits on the accent-colored selection background.
    @Environment(\.backgroundProminence) private var prominence

    private var pointSize: CGFloat { CGFloat(ConversationListTextSize.clamped(textSize)) }
    private var textScale: CGFloat { pointSize / CGFloat(ConversationListTextSize.defaultSize) }

    // At larger sizes, give the sender the full width rather than competing with the date.
    private var headerLayout: AnyLayout {
        pointSize >= 20
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    }

    var body: some View {
        if let message = thread.latestMessage {
            HStack(alignment: .top, spacing: checkbox == nil ? 7 : 5) {
                VStack(spacing: 6) {
                    Circle()
                        .fill(thread.isUnread ? (prominence == .increased ? Color.white : Color.accentColor) : .clear)
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                        .accessibilityHidden(true)
                    if let checkbox {
                        checkboxView(checkbox)
                    }
                }
                .frame(width: checkbox == nil ? 5 : 16)
                VStack(alignment: .leading, spacing: 2) {
                    headerLayout {
                        Text(thread.mailbox == .sent || thread.mailbox == .outbox ? message.recipient : message.senderName)
                            .font(.system(size: pointSize, weight: .semibold))
                            .lineLimit(1)
                        if pointSize < 20 { Spacer(minLength: 8) }
                        ZStack(alignment: .trailing) {
                            Text(message.date, format: Calendar.current.isDateInToday(message.date)
                                 ? .dateTime.hour().minute()
                                 : .dateTime.month(.abbreviated).day())
                                .font(.system(size: 11 * textScale))
                                .foregroundStyle(.secondary)
                                .opacity(isPending ? 0 : 1)
                            if isPending {
                                ProgressView()
                                    .controlSize(.mini)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    HStack(spacing: 5) {
                        Text(thread.subject)
                            .font(.system(size: pointSize, weight: thread.isUnread ? .medium : .regular))
                            .lineLimit(1)
                        if thread.messages.count > 1 {
                            Text(thread.messages.count, format: .number)
                                .font(.system(size: 10 * textScale).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                                .fixedSize()
                                .help(String(localized: "\(thread.messages.count) messages"))
                        }
                        Spacer(minLength: 4)
                        if thread.isImportant {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: pointSize))
                                .foregroundStyle(.secondary)
                        }
                        if thread.isStarred {
                            // Stays orange on the selection highlight, like Mimestream.
                            Image(systemName: "star.fill")
                                .font(.system(size: pointSize))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(thread.preview)
                        .font(.system(size: pointSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    AttachmentChip(attachments: message.attachments, textScale: textScale)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 6)
            // Keep the subject and preview when List measures a row with a compact height proposal.
            .fixedSize(horizontal: false, vertical: true)
            .background(NativeListRowSizing())
            .opacity(isPending ? 0.65 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPending)
            .contentShape(.rect)
            .onHover { isHovered = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription(of: message))
            .accessibilityValue(isPending ? String(localized: "Updating…") : "")
            .accessibilityAddTraits(checkbox?.isMarked == true ? .isSelected : [])
            .accessibilityActions {
                if let checkbox {
                    Button(checkbox.isMarked ? String(localized: "Uncheck") : String(localized: "Check")) { checkbox.toggle(false) }
                }
            }
        }
    }

    /// Takes no room of its own: it sits under the unread dot, and appears when the pointer is over the row.
    private func checkboxView(_ checkbox: RowCheckbox) -> some View {
        let isVisible = checkbox.isMarked || checkbox.isAlwaysVisible || isHovered
        return Toggle(isOn: Binding(
            get: { checkbox.isMarked },
            // The click's own modifiers, rather than the keys held by the time SwiftUI calls this.
            set: { _ in checkbox.toggle((NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).contains(.shift)) }
        )) {
            Text(checkbox.isMarked ? "Uncheck" : "Check")
        }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .controlSize(.small)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .help(String(localized: "Check to act on several conversations. Shift-click to check a range."))
        .accessibilityHidden(true)
    }

    /// One spoken summary per row: state first, then who, what and when, then the preview.
    private func accessibilityDescription(of message: MailMessage) -> String {
        var parts: [String] = []
        if thread.isUnread { parts.append(String(localized: "Unread")) }
        if thread.isStarred { parts.append(String(localized: "Starred")) }
        if thread.isImportant { parts.append(String(localized: "Important")) }
        parts.append(thread.mailbox == .sent ? String(localized: "To \(message.recipient)") : message.senderName)
        parts.append(thread.subject)
        if thread.messages.count > 1 {
            parts.append(String(localized: "\(thread.messages.count) messages", comment: "Number of messages in a conversation, spoken by VoiceOver"))
        }
        parts.append(message.date.formatted(date: .abbreviated, time: .shortened))
        parts.append(thread.preview)
        if let first = message.attachments.first {
            parts.append(String(localized: "Attachment \(first.filename)"))
            if message.attachments.count > 1 {
                parts.append(String(localized: "and \(message.attachments.count - 1) more"))
            }
        }
        return parts.joined(separator: ". ")
    }
}

/// The folder list of the Gmail reader.
struct MailboxSidebar: View {
    @Binding var selection: MailboxSelection?
    /// Whether to offer every account's inbox together, and its unread count.
    let showsAllInboxes: Bool
    let allInboxesBadge: Int
    /// Unread or draft counts to show next to a folder.
    let badges: [Mailbox: Int]
    let labels: LabelTree
    /// Whether a nested label shows what is inside it, by its path.
    let labelGroupExpansion: (String) -> Binding<Bool>
    @State private var showsMoreLabels = false

    var body: some View {
        List(selection: $selection) {
            Section("Mailboxes") {
                if showsAllInboxes {
                    Label(MailboxSelection.allInboxes.title, systemImage: MailboxSelection.allInboxes.symbol)
                        .badge(allInboxesBadge)
                        .tag(MailboxSelection.allInboxes)
                }
                ForEach(Mailbox.allCases) { mailbox in
                    Label(mailbox.title, systemImage: mailbox.symbol)
                        .badge(badges[mailbox] ?? 0)
                        .tag(MailboxSelection.folder(mailbox))
                }
            }
            if !labels.isEmpty {
                Section("Labels") {
                    ForEach(labels.roots) { LabelRow(node: $0, expansion: labelGroupExpansion) }
                    if !labels.more.isEmpty {
                        moreLabelsRow
                        if showsMoreLabels {
                            ForEach(labels.more) { LabelRow(node: $0, expansion: labelGroupExpansion) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// Opens or closes the labels Gmail doesn't list, like Gmail's own More. The chevron takes the icon's place,
    /// where it has the icons' color: the system disclosure triangle is too faint in a dark sidebar.
    private var moreLabelsRow: some View {
        Label {
            Text("More")
        } icon: {
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(showsMoreLabels ? 90 : 0))
        }
        .contentShape(.rect)
        .onTapGesture { withAnimation(.snappy) { showsMoreLabels.toggle() } }
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(showsMoreLabels ? String(localized: "Expanded") : String(localized: "Collapsed"))
        .accessibilityAction { showsMoreLabels.toggle() }
    }
}

/// A label in the sidebar, with the labels nested in it.
private struct LabelRow: View {
    let node: LabelNode
    let expansion: (String) -> Binding<Bool>

    var body: some View {
        if node.children.isEmpty {
            title(unreadThreads: node.unreadThreads)
        } else {
            let isExpanded = expansion(node.path)
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(node.children) { LabelRow(node: $0, expansion: expansion) }
            } label: {
                let row = title(unreadThreads: isExpanded.wrappedValue ? node.unreadThreads : node.unreadThreadsIncludingChildren)
                if node.label == nil {
                    // A parent that is only part of its children's names has nothing to open, so a click expands it instead.
                    row.contentShape(.rect).onTapGesture { isExpanded.wrappedValue.toggle() }
                } else {
                    row
                }
            }
        }
    }

    @ViewBuilder
    private func title(unreadThreads: Int) -> some View {
        // The sidebar ignores a weight set on the whole Label.
        let row = Label {
            Text(node.title).fontWeight(unreadThreads > 0 ? .semibold : nil).lineLimit(1)
        } icon: {
            Image(systemName: "tag")
        }
        .badge(unreadThreads)
        if let label = node.label {
            row.tag(MailboxSelection.folder(.label(label.id)))
        } else {
            row
        }
    }
}
