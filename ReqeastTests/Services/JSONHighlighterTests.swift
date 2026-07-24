import Testing
@testable import Reqeast

@Suite("JSONHighlighter")
struct JSONHighlighterTests {

    @Test func highlightsEmptyString() {
        let result = JSONHighlighter.highlight("", theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == "")
    }

    @Test func highlightsSimpleKeyValue() {
        let json = #"{"name": "test"}"#
        let result = JSONHighlighter.highlight(json, theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == json)
    }

    @Test func highlightsNumbers() {
        let json = #"{"count": 42}"#
        let result = JSONHighlighter.highlight(json, theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == json)
    }

    @Test func highlightsBooleans() {
        let json = #"{"active": true, "deleted": false}"#
        let result = JSONHighlighter.highlight(json, theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == json)
    }

    @Test func highlightsNull() {
        let json = #"{"value": null}"#
        let result = JSONHighlighter.highlight(json, theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == json)
    }

    @Test func preservesWhitespace() {
        let json = "{\n  \"key\": \"value\"\n}"
        let result = JSONHighlighter.highlight(json, theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == json)
    }

    @Test func fallsBackOnLargeInput() {
        let large = String(repeating: "x", count: 200_000)
        let result = JSONHighlighter.highlight(large, theme: .responseDarkSwiftUI)
        #expect(String(result.characters) == large)
    }
}
