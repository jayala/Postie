import Foundation
import Testing
import WebKit
@testable import Postie

/// Loads the editor's real page in a real web view, as the composer does.
@MainActor
private final class EditorHarness: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: EditorWebView
    private(set) var messages: [[String: Any]] = []
    private var readyContinuation: CheckedContinuation<Void, Never>?

    init(html: String) {
        webView = EditorWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: RichTextPolicy.configuration())
        super.init()
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, contentWorld: RichTextPolicy.world, name: RichTextPolicy.handler)
        webView.loadHTMLString(RichTextPolicy.document(html, label: "Message body"), baseURL: nil)
    }

    func waitUntilReady() async {
        if messages.contains(where: { $0["type"] as? String == "ready" }) { return }
        await withCheckedContinuation { readyContinuation = $0 }
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any] else { return }
            messages.append(body)
            if body["type"] as? String == "ready" { readyContinuation?.resume(); readyContinuation = nil }
        }
    }

    func call(_ expression: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript("return " + expression, arguments: arguments, contentWorld: RichTextPolicy.world)
    }

    func snapshot() async throws -> EditorContent {
        let value = try await call("postieEditor.snapshot()") as? [String: Any]
        return try #require(value.flatMap(EditorContent.init))
    }

    /// How wide the page is, which is wider than the view when something in it does not wrap.
    func contentWidth() async throws -> Int {
        try #require(try await call("document.documentElement.scrollWidth") as? Int)
    }

    /// How many lines an element's text takes up.
    func lines(of id: String) async throws -> Int {
        let script = """
        (() => {
            const text = document.createRange();
            text.selectNodeContents(document.getElementById('\(id)'));
            return text.getClientRects().length;
        })()
        """
        return try #require(try await call(script) as? Int)
    }
}

@Suite("HTML editor", .timeLimit(.minutes(1)))
@MainActor
struct HTMLEditorTests {
    @Test("The editor starts with the given markup although page scripts are off")
    func loads() async throws {
        let harness = EditorHarness(html: "<div>Hello <b>there</b></div>")
        await harness.waitUntilReady()
        let content = try await harness.snapshot()
        #expect(content.html == "<div>Hello <b>there</b></div>")
        #expect(content.text == "Hello there")
        #expect(content.ownText == "Hello there")
        // Scripts in the page itself do not run, only the app's.
        let pageScript = try await harness.webView.evaluateJavaScript("typeof window.postieEditor")
        #expect(pageScript as? String == "undefined")
    }

    @Test("Quoted text is plain text with markers and does not count as typed")
    func quote() async throws {
        let quote = HTMLText.emptyLine + "<div class=\"gmail_quote\"><div class=\"gmail_attr\">On Monday, A wrote:<br></div>"
            + "<blockquote class=\"gmail_quote\">Line one<br>Line two<ul><li>Item</li></ul>"
            + "<a href=\"https://example.com\">site</a></blockquote></div>"
        let harness = EditorHarness(html: quote)
        await harness.waitUntilReady()
        let content = try await harness.snapshot()
        #expect(content.ownText.isEmpty)
        #expect(content.text.contains("On Monday, A wrote:\n> Line one\n> Line two\n> \u{2022} Item"))
        #expect(content.text.contains("site (https://example.com)"))
    }

    @Test("A column of a quoted table keeps its words whole beside a cell that claims all the width", arguments: [
        labelledTable(value: "<strong>Alex Doe</strong>"),
        labelledTable(value: "<a href=\"\(longAddress)\">\(longAddress)</a>"),
        labelledTable(value: longAddress),
        // Text that may break anywhere must not pass that on to a table next to it.
        "<div>\(longRule)\(labelledTable(value: "Alex Doe"))</div>"
    ])
    func quotedLabelColumn(table: String) async throws {
        let harness = EditorHarness(html: HTMLText.emptyLine + "<div class=\"gmail_quote\"><blockquote class=\"gmail_quote\">\(table)</blockquote></div>")
        await harness.waitUntilReady()
        #expect(try await harness.lines(of: "label") == 1)
        #expect(try await harness.contentWidth() <= 600)
    }

    @Test("Long unbroken text wraps instead of making the message wider than its view, without changing what is sent", arguments: [
        "<table><tbody><tr><td>\(longAddress)</td></tr></tbody></table>",
        "<table><tbody><tr><td><a href=\"\(longAddress)\">\(longAddress)</a></td></tr></tbody></table>",
        "<table><tbody><tr><td>\(longRule)</td></tr></tbody></table>",
        // Emails often ask for this themselves, which would otherwise win over the editor's style sheet.
        "<table><tbody><tr><td style=\"word-wrap: break-word\">\(longAddress)</td></tr></tbody></table>",
        "<div>\(longAddress)</div>"
    ])
    func longTextWraps(html: String) async throws {
        let harness = EditorHarness(html: html)
        await harness.waitUntilReady()
        #expect(try await harness.contentWidth() <= 600)
        #expect(harness.messages.first { $0["type"] as? String == "ready" }?["html"] as? String == html)
        #expect(try await harness.snapshot().html == html)
    }

    @Test("A long address added later wraps too, and what is sent stays as written")
    func longTextAddedLater() async throws {
        let harness = EditorHarness(html: "<div>Hello</div>")
        await harness.waitUntilReady()
        let table = "<table><tbody><tr><td>\(longAddress)</td></tr></tbody></table>"
        _ = try await harness.webView.callAsyncJavaScript(
            "const e = document.getElementById('editor'); e.focus(); document.execCommand('insertHTML', false, table); e.dispatchEvent(new Event('input'))",
            arguments: ["table": table], contentWorld: RichTextPolicy.world
        )
        try await Task.sleep(for: .milliseconds(400))
        #expect(try await harness.contentWidth() <= 600)
        let change = try #require(harness.messages.last { $0["type"] as? String == "change" })
        #expect((change["html"] as? String)?.contains(table) == true)
    }

    @Test("Marking long text while typing leaves the cursor and Undo alone")
    func longTextKeepsEditing() async throws {
        let harness = EditorHarness(html: "<div>Hello</div>")
        // Undo belongs to the window.
        let window = NSWindow(contentRect: harness.webView.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = harness.webView
        await harness.waitUntilReady()
        let type = "document.execCommand('insertText', false, typed); document.getElementById('editor').dispatchEvent(new Event('input'))"
        _ = try await harness.webView.callAsyncJavaScript(
            "const e = document.getElementById('editor'); e.focus(); getSelection().selectAllChildren(e.firstChild); getSelection().collapseToEnd(); " + type,
            arguments: ["typed": " " + longAddress], contentWorld: RichTextPolicy.world
        )
        try await Task.sleep(for: .milliseconds(400))
        let marked = try await harness.call("document.querySelector('#editor [\(RichTextPolicy.longTextMark)]') !== null") as? Bool
        #expect(marked == true)
        _ = try await harness.webView.callAsyncJavaScript(type, arguments: ["typed": "!"], contentWorld: RichTextPolicy.world)
        #expect(try await harness.snapshot().html == "<div>Hello \(longAddress)!</div>")
        _ = try await harness.call("document.execCommand('undo')")
        #expect(try await harness.snapshot().html.contains("!") == false)
    }

    @Test("Formatting commands change the markup")
    func formatting() async throws {
        let harness = EditorHarness(html: "<div>Hello</div>")
        await harness.waitUntilReady()
        _ = try await harness.webView.evaluateJavaScript(
            "document.getElementById('editor').focus(); document.execCommand('selectAll')", contentWorld: RichTextPolicy.world
        )
        _ = try await harness.call("postieEditor.exec(command)", ["command": "bold"])
        _ = try await harness.call("postieEditor.exec(command)", ["command": "insertUnorderedList"])
        var html = try await harness.snapshot().html
        #expect(html.contains("<b>Hello</b>") || html.contains("<strong>Hello</strong>"))
        #expect(html.contains("<ul>"))
        _ = try await harness.call("postieEditor.link(url)", ["url": "https://example.com"])
        html = try await harness.snapshot().html
        #expect(html.contains("href=\"https://example.com\""))
    }

    @Test("Edits are reported after a short pause")
    func reportsChanges() async throws {
        let harness = EditorHarness(html: "")
        await harness.waitUntilReady()
        _ = try await harness.webView.evaluateJavaScript(
            "const e = document.getElementById('editor'); e.focus(); document.execCommand('insertText', false, 'Typed'); e.dispatchEvent(new Event('input'))",
            contentWorld: RichTextPolicy.world
        )
        try await Task.sleep(for: .milliseconds(400))
        let change = harness.messages.last { $0["type"] as? String == "change" }
        #expect(change?["own"] as? String == "Typed")
    }

    @Test("A signature goes under the typed text and above the quote, and is not counted as typed")
    func signature() async throws {
        let quote = HTMLText.emptyLine + "<div class=\"gmail_quote\"><blockquote>Original</blockquote></div>"
        let harness = EditorHarness(html: quote)
        await harness.waitUntilReady()
        _ = try await harness.call("postieEditor.setSignature(html)", ["html": "Alex<br>Postie"])
        let content = try await harness.snapshot()
        let signature = try #require(content.html.range(of: "class=\"gmail_signature\""))
        let original = try #require(content.html.range(of: "class=\"gmail_quote\""))
        #expect(signature.lowerBound < original.lowerBound)
        #expect(content.text.contains("\nAlex\nPostie"))
        #expect(content.ownText.isEmpty)

        _ = try await harness.call("postieEditor.setSignature(html)", ["html": "New"])
        let replaced = try await harness.snapshot()
        #expect(replaced.html.components(separatedBy: "class=\"gmail_signature\"").count == 2)
        #expect(replaced.text.contains("\nNew") && !replaced.text.contains("Alex"))

        _ = try await harness.call("postieEditor.setSignature(html)", ["html": ""])
        #expect(try await harness.snapshot().html.contains("gmail_signature") == false)
    }

    @Test("On a new message the signature leaves a line to type on above it")
    func signatureOnNewMessage() async throws {
        let harness = EditorHarness(html: "")
        await harness.waitUntilReady()
        _ = try await harness.call("postieEditor.setSignature(html)", ["html": "Alex"])
        let html = try await harness.snapshot().html
        #expect(html.hasPrefix("<div><br></div><div class=\"gmail_signature\""))
    }
}
