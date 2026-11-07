import Testing
@testable import Postie

@Suite("Tables placed straight inside tables")
struct EmailTableNestingTests {
    @Test("A table where a row or cell should be gets one of its own, as Gmail gives it", arguments: [
        ("<table><table id=\"block\"></table></table>",
         "<table><tr><td><table id=\"block\"></table></table>"),
        ("<table><tbody><table></table></tbody></table>",
         "<table><tbody><tr><td><table></table></tbody></table>"),
        ("<table><tr><table></table></tr></table>",
         "<table><tr><td><table></table></tr></table>"),
        ("<TABLE><Table></Table></TABLE>",
         "<TABLE><tr><td><Table></Table></TABLE>"),
        // Blocks in a row share the cell, as the rows after them would close it.
        ("<table><table></table><table></table></table>",
         "<table><tr><td><table></table><table></table></table>"),
        ("<table><table></table><tr><td>Row</td></tr><table></table></table>",
         "<table><tr><td><table></table><tr><td>Row</td></tr><tr><td><table></table></table>"),
        // Rows and cells that end without an end tag.
        ("<table><tr><td>One<tr><table></table></table>",
         "<table><tr><td>One<tr><td><table></table></table>"),
        ("<table><tr><td>One</td></tr><table></table></table>",
         "<table><tr><td>One</td></tr><tr><td><table></table></table>"),
        ("<table>Olá<table>São Paulo</table></table>",
         "<table>Olá<tr><td><table>São Paulo</table></table>")
    ])
    func repairsNesting(input: (String, String)) {
        #expect(EmailTableNesting.repaired(input.0) == input.1)
    }

    @Test("Tables that are nested properly, or only written in text, are left as they are", arguments: [
        "<table><tr><td><table><tr><td>Nested</td></tr></table></td></tr></table>",
        "<table><tr><td>One</td></tr></table><table></table>",
        "<div><table></table></div><p>1 < 2</p>",
        "<table><tr><td><table></table><td><table></table></table>",
        "<table><caption>Trip</caption><tr><td><table></table></td></tr></table>",
        // End tags that aren't tags must not close the cell around the inner table.
        "<table><tr><td><!-- </td></tr> --><table></table></td></tr></table>",
        "<table><tr><td title=\"a > </td></tr>\"><table></table></td></tr></table>",
        "<table><tr><td data-x='</tr>'><table></table></td></tr></table>",
        "<table><tr><td><style>td::after { content: \"</td></tr>\"; }</style><table></table></td></tr></table>",
        "<table><tr><td><title></td></tr></TITLE><table></table></td></tr></table>",
        "<!doctype html><html><head><style>table > table { color: red }</style></head><body>No tables</body></html>",
        "Plain text with no markup"
    ])
    func leavesWellFormedTables(html: String) {
        #expect(EmailTableNesting.repaired(html) == html)
    }

    @Test("A comment that HTML closes early still hides nothing after it")
    func shortComments() {
        #expect(EmailTableNesting.repaired("<table><!--><table></table></table>") == "<table><!--><tr><td><table></table></table>")
        #expect(EmailTableNesting.repaired("<table><!---><table></table></table>") == "<table><!---><tr><td><table></table></table>")
        #expect(EmailTableNesting.repaired("<table><!-- a --!><table></table></table>") == "<table><!-- a --!><tr><td><table></table></table>")
    }
}
