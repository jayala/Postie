import SwiftUI

/// Conversation context stays visible independently of the message scroll position.
struct ConversationHeaderView: View {
    let thread: MailThread
    let canModifyLabels: Bool
    let isDraft: Bool
    let toggleStar: () -> Void
    let toggleImportant: () -> Void

    private var importantActionTitle: String {
        thread.isImportant ? String(localized: "Mark as Not Important") : String(localized: "Mark as Important")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SubjectLayout {
                    Text(thread.subject)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .help(thread.subject)
                        .accessibilityAddTraits(.isHeader)
                        .contextMenu {
                            Button("Copy Subject", systemImage: "doc.on.doc", action: copySubject)
                        }
                    if isDraft {
                        LabelChip(name: Mailbox.drafts.title)
                    }
                    ForEach(thread.labels, id: \.self) { LabelChip(name: $0) }
                }

                if thread.messages.count > 1 {
                    Text("\(thread.messages.count) messages")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: toggleImportant) {
                Image(systemName: thread.isImportant ? "exclamationmark.circle.fill" : "exclamationmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(!canModifyLabels)
            .help(canModifyLabels ? importantActionTitle : String(localized: "Importance cannot be changed yet."))
            .accessibilityLabel(importantActionTitle)

            Button(action: toggleStar) {
                Image(systemName: thread.isStarred ? "star.fill" : "star")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(!canModifyLabels)
            .help(canModifyLabels
                  ? (thread.isStarred ? String(localized: "Remove star") : String(localized: "Star conversation"))
                  : String(localized: "Stars cannot be changed yet."))
            .accessibilityLabel(thread.isStarred ? String(localized: "Remove star") : String(localized: "Star conversation"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func copySubject() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(thread.subject, forType: .string)
    }
}

private struct LabelChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// The subject followed by its labels on the same line, moving on to the next line for whatever does not fit.
private struct SubjectLayout: Layout {
    private let spacing: CGFloat = 6
    private let lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let frames = frames(of: subviews, width: proposal.width)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        for (subview, frame) in zip(subviews, frames(of: subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    /// Whatever sits beside this layout lines up with the subject's first line, not with the last label.
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Void) -> CGFloat? {
        guard guide == .firstTextBaseline, let subject = subviews.first,
              let frame = frames(of: subviews, width: bounds.width).first else { return nil }
        return bounds.minY + frame.minY + subject.dimensions(in: ProposedViewSize(frame.size))[.firstTextBaseline]
    }

    private func frames(of subviews: Subviews, width: CGFloat?) -> [CGRect] {
        var frames: [CGRect] = []
        var lineStart = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        // A label is shorter than the subject, so it sits in the middle of the line.
        func centerLine() {
            for index in lineStart..<frames.count {
                frames[index].origin.y += (lineHeight - frames[index].height) / 2
            }
        }
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width ?? .infinity {
                centerLine()
                lineStart = frames.count
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        centerLine()
        return frames
    }
}
