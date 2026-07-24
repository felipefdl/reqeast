import Testing
@testable import Reqeast

@Suite("HTMLHighlighter")
struct HTMLHighlighterTests {

    @Test func highlightsEmptyString() {
        let result = HTMLHighlighter.highlight("", theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == "")
    }

    @Test func highlightsSimpleTag() {
        let html = "<div>hello</div>"
        let result = HTMLHighlighter.highlight(html, theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == html)
    }

    @Test func highlightsAttributes() {
        let html = #"<a href="url">link</a>"#
        let result = HTMLHighlighter.highlight(html, theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == html)
    }

    @Test func highlightsComment() {
        let html = "<!-- comment -->"
        let result = HTMLHighlighter.highlight(html, theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == html)
    }

    @Test func highlightsSelfClosingTag() {
        let html = "<br/>"
        let result = HTMLHighlighter.highlight(html, theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == html)
    }

    @Test func preservesWhitespace() {
        let html = "<div>\n  <p>text</p>\n</div>"
        let result = HTMLHighlighter.highlight(html, theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == html)
    }

    @Test func fallsBackOnLargeInput() {
        let large = String(repeating: "x", count: 200_000)
        let result = HTMLHighlighter.highlight(large, theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == large)
    }
}
