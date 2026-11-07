import Foundation

/// Mail is often written with a table placed straight inside another table, where a row or a cell should be,
/// as content blocks dropped into a template. Gmail puts such a table in a cell of its own. Browsers
/// follow HTML5 instead, which ends the outer table there, so everything after it lands in the wrong place, such
/// as a footer outside the column of the message. Giving those tables the row and cell they leave out lays the
/// mail out as Gmail shows it.
///
/// This follows the tables with a small part of HTML5's tokenizer: comments, raw text such as styles, and
/// quoted attribute values are skipped, so a `<table>` written inside them is not counted.
nonisolated enum EmailTableNesting {
    private enum Level { case table, section, row, cell, caption }

    /// `html`, with an implied `<tr><td>` or `<td>` before each table that would otherwise end the table around it.
    static func repaired(_ html: String) -> String {
        let bytes = Array(html.utf8)
        var tracker = TableTracker(bytes: bytes)
        let insertions = tracker.insertions()
        guard !insertions.isEmpty else { return html }
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count + insertions.count * 8)
        var start = 0
        for (offset, markup) in insertions {
            result.append(contentsOf: bytes[start..<offset])
            result.append(contentsOf: markup.utf8)
            start = offset
        }
        result.append(contentsOf: bytes[start...])
        return String(decoding: result, as: UTF8.self)
    }

    private struct TableTracker {
        let bytes: [UInt8]
        var position = 0
        var levels: [Level] = []
        var found: [(Int, String)] = []

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func insertions() -> [(Int, String)] {
            while let open = bytes[position...].firstIndex(of: .lessThan) {
                position = open
                scanMarkup()
            }
            return found
        }

        // MARK: Tokens

        private mutating func scanMarkup() {
            let start = position
            let next = byte(at: start + 1)
            if next == .exclamation, byte(at: start + 2) == .hyphen, byte(at: start + 3) == .hyphen {
                position = commentEnd(after: start + 4)
            } else if next == .exclamation || next == .question {
                position = afterNext(.greaterThan, from: start + 2) // A doctype, or a bogus comment such as `<![endif]>`.
            } else if next == .slash, let first = byte(at: start + 2), first.isASCIILetter {
                let (name, end) = tagName(from: start + 2)
                position = afterTag(from: end)
                endTag(name)
            } else if next == .slash {
                position = byte(at: start + 2) == .greaterThan ? start + 3 : afterNext(.greaterThan, from: start + 2)
            } else if let first = next, first.isASCIILetter {
                let (name, end) = tagName(from: start + 1)
                startTag(name, at: start)
                position = afterTag(from: end)
                skipText(of: name)
            } else {
                position = start + 1 // A `<` that is just text.
            }
        }

        /// `<!-->` and `<!--->` are whole comments. Others end at `-->` or `--!>`, or run to the end of the mail.
        private func commentEnd(after start: Int) -> Int {
            if byte(at: start) == .greaterThan { return start + 1 }
            if byte(at: start) == .hyphen, byte(at: start + 1) == .greaterThan { return start + 2 }
            var index = start
            while index + 2 < bytes.count {
                if bytes[index] == .hyphen, bytes[index + 1] == .hyphen {
                    if bytes[index + 2] == .greaterThan { return index + 3 }
                    if bytes[index + 2] == .exclamation, byte(at: index + 3) == .greaterThan { return index + 4 }
                }
                index += 1
            }
            return bytes.count
        }

        private func tagName(from start: Int) -> (String, Int) {
            var end = start
            while end < bytes.count, !bytes[end].isTagNameEnd { end += 1 }
            let name = bytes[start..<end].prefix(16).map { $0.isASCIIUppercase ? $0 + 32 : $0 }
            return (String(decoding: name, as: UTF8.self), end)
        }

        private enum AttributeState { case beforeName, name, afterName, beforeValue, quoted(UInt8), unquoted, afterQuoted }

        /// The position after the tag's `>`, found with HTML5's attribute states so that a `>` in a quoted value doesn't end it.
        private func afterTag(from start: Int) -> Int {
            var state = AttributeState.beforeName
            var index = start
            while index < bytes.count {
                let byte = bytes[index]
                switch state {
                case .beforeName:
                    if byte == .greaterThan { return index + 1 }
                    if !byte.isHTMLSpace, byte != .slash { state = .name }
                case .name:
                    if byte == .greaterThan { return index + 1 }
                    if byte.isHTMLSpace { state = .afterName } else if byte == .slash { state = .beforeName } else if byte == .equals { state = .beforeValue }
                case .afterName:
                    if byte == .greaterThan { return index + 1 }
                    if byte == .slash { state = .beforeName } else if byte == .equals { state = .beforeValue } else if !byte.isHTMLSpace { state = .name }
                case .beforeValue:
                    if byte == .greaterThan { return index + 1 }
                    if byte == .quote || byte == .apostrophe { state = .quoted(byte) } else if !byte.isHTMLSpace { state = .unquoted }
                case .quoted(let quote):
                    if byte == quote { state = .afterQuoted }
                case .unquoted:
                    if byte == .greaterThan { return index + 1 }
                    if byte.isHTMLSpace { state = .beforeName }
                case .afterQuoted:
                    if byte == .greaterThan { return index + 1 }
                    state = .beforeName
                    if !byte.isHTMLSpace, byte != .slash { continue } // The next attribute starts here.
                }
                index += 1
            }
            return bytes.count
        }

        /// Styles, scripts, titles and the like hold text, not tags, up to their own end tag.
        private mutating func skipText(of name: String) {
            switch name {
            case "plaintext":
                position = bytes.count
            case "style", "script", "xmp", "iframe", "noembed", "noframes", "title", "textarea":
                let end = Array("</\(name)".utf8)
                var index = position
                while let open = bytes[index...].firstIndex(of: .lessThan) {
                    let candidate = bytes[open...].prefix(end.count).map { $0.isASCIIUppercase ? $0 + 32 : $0 }
                    if candidate.elementsEqual(end), byte(at: open + end.count).map({ $0.isTagNameEnd }) ?? true {
                        position = open
                        return
                    }
                    index = open + 1
                }
                position = bytes.count
            default:
                break
            }
        }

        private func afterNext(_ target: UInt8, from start: Int) -> Int {
            guard start < bytes.count, let index = bytes[start...].firstIndex(of: target) else { return bytes.count }
            return index + 1
        }

        private func byte(at index: Int) -> UInt8? { index < bytes.count ? bytes[index] : nil }

        // MARK: Tables

        /// What is open in the innermost table, which a new part of a table closes, as HTML5 does.
        private func innermost(_ level: Level) -> Int? {
            guard let table = levels.lastIndex(of: .table) else { return nil }
            return levels[(table + 1)...].lastIndex(of: level)
        }

        private mutating func startTag(_ name: String, at offset: Int) {
            switch name {
            case "table":
                switch levels.last {
                case .table:
                    found.append((offset, "<tr><td>"))
                    levels += [.section, .row, .cell]
                case .section:
                    found.append((offset, "<tr><td>"))
                    levels += [.row, .cell]
                case .row:
                    found.append((offset, "<td>"))
                    levels.append(.cell)
                case .caption:
                    // HTML5 ends the caption and its table here. Tables in captions are too rare to change that.
                    if let table = levels.lastIndex(of: .table) { levels.removeSubrange(table...) }
                case .cell, .none:
                    break
                }
                levels.append(.table)
            case "tbody", "thead", "tfoot":
                guard let table = levels.lastIndex(of: .table) else { return }
                levels.removeSubrange((table + 1)...)
                levels.append(.section)
            case "tr":
                guard let table = levels.lastIndex(of: .table) else { return }
                if let section = innermost(.section) {
                    levels.removeSubrange((section + 1)...)
                } else {
                    levels.removeSubrange((table + 1)...)
                    levels.append(.section)
                }
                levels.append(.row)
            case "td", "th":
                guard let table = levels.lastIndex(of: .table) else { return }
                if let row = innermost(.row) {
                    levels.removeSubrange((row + 1)...)
                } else if let section = innermost(.section) {
                    levels.removeSubrange((section + 1)...)
                    levels.append(.row)
                } else {
                    levels.removeSubrange((table + 1)...)
                    levels += [.section, .row]
                }
                levels.append(.cell)
            case "caption", "colgroup", "col":
                guard let table = levels.lastIndex(of: .table) else { return }
                levels.removeSubrange((table + 1)...)
                if name == "caption" { levels.append(.caption) }
            default:
                break
            }
        }

        private mutating func endTag(_ name: String) {
            let level: Level? = switch name {
            case "table": .table
            case "tbody", "thead", "tfoot": .section
            case "tr": .row
            case "td", "th": .cell
            case "caption": .caption
            default: nil
            }
            guard let level else { return }
            let open = level == .table ? levels.lastIndex(of: .table) : innermost(level)
            if let open { levels.removeSubrange(open...) }
        }
    }
}

nonisolated private extension UInt8 {
    static let lessThan = UInt8(ascii: "<"), greaterThan = UInt8(ascii: ">"), slash = UInt8(ascii: "/")
    static let exclamation = UInt8(ascii: "!"), question = UInt8(ascii: "?"), hyphen = UInt8(ascii: "-")
    static let equals = UInt8(ascii: "="), quote = UInt8(ascii: "\""), apostrophe = UInt8(ascii: "'")

    var isASCIIUppercase: Bool { self >= UInt8(ascii: "A") && self <= UInt8(ascii: "Z") }
    var isASCIILetter: Bool { isASCIIUppercase || (self >= UInt8(ascii: "a") && self <= UInt8(ascii: "z")) }
    /// HTML's whitespace: tab, line feed, form feed, carriage return and space.
    var isHTMLSpace: Bool { self == 0x09 || self == 0x0A || self == 0x0C || self == 0x0D || self == 0x20 }
    var isTagNameEnd: Bool { isHTMLSpace || self == .slash || self == .greaterThan }
}
