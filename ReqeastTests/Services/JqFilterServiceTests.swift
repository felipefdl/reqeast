//
//  JqFilterServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("JqFilterService.unquoteStrings")
struct JqFilterServiceTests {
    @Test func simpleQuotedString() {
        #expect(JqFilterService.unquoteStrings("\"test\"") == "test")
    }

    @Test func stringWithEscapedQuotes() {
        #expect(JqFilterService.unquoteStrings("\"hello \\\"world\\\"\"") == "hello \"world\"")
    }

    @Test func stringWithEscapedNewline() {
        #expect(JqFilterService.unquoteStrings("\"line1\\nline2\"") == "line1\nline2")
    }

    @Test func stringWithUnicodeEscape() {
        #expect(JqFilterService.unquoteStrings("\"\\u00e9\"") == "\u{00e9}")
    }

    @Test func stringWithBackslash() {
        #expect(JqFilterService.unquoteStrings("\"path\\\\to\\\\file\"") == "path\\to\\file")
    }

    @Test func stringWithTab() {
        #expect(JqFilterService.unquoteStrings("\"col1\\tcol2\"") == "col1\tcol2")
    }

    @Test func emptyQuotedString() {
        #expect(JqFilterService.unquoteStrings("\"\"") == "")
    }

    @Test func number() {
        #expect(JqFilterService.unquoteStrings("42") == "42")
    }

    @Test func booleanTrue() {
        #expect(JqFilterService.unquoteStrings("true") == "true")
    }

    @Test func booleanFalse() {
        #expect(JqFilterService.unquoteStrings("false") == "false")
    }

    @Test func null() {
        #expect(JqFilterService.unquoteStrings("null") == "null")
    }

    @Test func jsonObject() {
        #expect(JqFilterService.unquoteStrings("{\"a\":1}") == "{\"a\":1}")
    }

    @Test func jsonArray() {
        #expect(JqFilterService.unquoteStrings("[1,2,3]") == "[1,2,3]")
    }

    @Test func multipleLinesMultipleTypes() {
        let input = "\"hello\"\n42\n{\"key\":\"val\"}"
        let expected = "hello\n42\n{\"key\":\"val\"}"
        #expect(JqFilterService.unquoteStrings(input) == expected)
    }

    @Test func emptyInput() {
        #expect(JqFilterService.unquoteStrings("") == "")
    }

    @Test func singleNewline() {
        #expect(JqFilterService.unquoteStrings("\n") == "\n")
    }

    @Test func veryLongString() {
        let long = String(repeating: "a", count: 10_000)
        let input = "\"\(long)\""
        let result = JqFilterService.unquoteStrings(input)
        #expect(result == long)
        #expect(result.count == 10_000)
    }

    @Test func allJsonEscapeTypes() {
        let input = "\"tab\\there\\nnewline\\rreturn\\\\backslash\\\"/quote\""
        let expected = "tab\there\nnewline\rreturn\\backslash\"/quote"
        #expect(JqFilterService.unquoteStrings(input) == expected)
    }

    @Test func malformedUnterminated() {
        #expect(JqFilterService.unquoteStrings("\"unterminated") == "\"unterminated")
    }

    @Test func nonUtf8SafeContent() {
        let input = "\"normal text\""
        #expect(JqFilterService.unquoteStrings(input) == "normal text")
    }

    @Test func multipleQuotedStringsOnSeparateLines() {
        let input = "\"first\"\n\"second\"\n\"third\""
        let expected = "first\nsecond\nthird"
        #expect(JqFilterService.unquoteStrings(input) == expected)
    }

    @Test func stringWithOnlyWhitespace() {
        let input = "\"   \""
        #expect(JqFilterService.unquoteStrings(input) == "   ")
    }

    @Test func mixedEmptyAndNonEmptyLines() {
        let input = "\"hello\"\n\n\"world\""
        let expected = "hello\n\nworld"
        #expect(JqFilterService.unquoteStrings(input) == expected)
    }
}

@Suite("JqFilterService.evaluate")
struct JqFilterEvaluateTests {
    @Test func validFieldAccess() {
        let result = JqFilterService.evaluate(
            expression: ".name",
            json: #"{"name": "test"}"#
        )
        if case .success(let text) = result {
            #expect(text == #""test""#)
        } else {
            Issue.record("Expected success")
        }
    }

    @Test func typeErrorReturnsCleanMessage() {
        let result = JqFilterService.evaluate(
            expression: ".data.foo",
            json: #"{"data": "not an object"}"#
        )
        if case .failure(let message) = result {
            // jaq wording varies by version ("cannot index" vs "cannot use").
            #expect(message.contains("cannot index") || message.contains("cannot use"))
            #expect(!message.contains("ReqeastError"))
            #expect(!message.contains("InvalidConfig"))
            #expect(!message.contains("Str("))
        } else {
            Issue.record("Expected failure for indexing a string")
        }
    }

    @Test func invalidFilterReturnsFailure() {
        let result = JqFilterService.evaluate(
            expression: ".[invalid",
            json: #"{"a": 1}"#
        )
        if case .failure = result {
            // expected
        } else {
            Issue.record("Expected failure for invalid filter syntax")
        }
    }

    @Test func missingFieldReturnsNull() {
        let result = JqFilterService.evaluate(
            expression: ".missing",
            json: #"{"a": 1}"#
        )
        if case .success(let text) = result {
            #expect(text == "null")
        } else {
            Issue.record("Expected success with null")
        }
    }
}

@Suite("JqFilterService.deepParseJsonStrings")
struct JqFilterDeepParseTests {
    @Test func parsesEmbeddedJsonObject() {
        let input = #"{"data": "{\"room_id\": \"general\", \"content\": \"Hello!\"}"}"#
        let result = JqFilterService.deepParseJsonStrings(input)
        let parsed = try! JSONSerialization.jsonObject(with: result.data(using: .utf8)!) as! [String: Any]
        let data = parsed["data"] as! [String: Any]
        #expect(data["room_id"] as? String == "general")
        #expect(data["content"] as? String == "Hello!")
    }

    @Test func parsesNestedEmbeddedJson() {
        // Outer JSON whose .data is a JSON-encoded string whose .nested is another JSON-encoded
        // string with {"key": "value"}. Uses JSONSerialization to build the input so the
        // escaping is guaranteed to be correct.
        let innerObj: [String: Any] = ["key": "value"]
        let innerStr = String(data: try! JSONSerialization.data(withJSONObject: innerObj), encoding: .utf8)!
        let middleObj: [String: Any] = ["nested": innerStr]
        let middleStr = String(data: try! JSONSerialization.data(withJSONObject: middleObj), encoding: .utf8)!
        let outerObj: [String: Any] = ["data": middleStr]
        let outer = String(data: try! JSONSerialization.data(withJSONObject: outerObj), encoding: .utf8)!

        let result = JqFilterService.deepParseJsonStrings(outer)
        let parsed = try! JSONSerialization.jsonObject(with: result.data(using: .utf8)!) as! [String: Any]
        let data = parsed["data"] as! [String: Any]
        let nested = data["nested"] as! [String: Any]
        #expect(nested["key"] as? String == "value")
    }

    @Test func leavesPlainStringsAlone() {
        let input = #"{"name": "not json", "count": 42}"#
        let result = JqFilterService.deepParseJsonStrings(input)
        let parsed = try! JSONSerialization.jsonObject(with: result.data(using: .utf8)!) as! [String: Any]
        #expect(parsed["name"] as? String == "not json")
        #expect(parsed["count"] as? Int == 42)
    }

    @Test func handlesArraysWithEmbeddedJson() {
        let input = #"{"items": ["{\"id\": 1}", "{\"id\": 2}"]}"#
        let result = JqFilterService.deepParseJsonStrings(input)
        let parsed = try! JSONSerialization.jsonObject(with: result.data(using: .utf8)!) as! [String: Any]
        let items = parsed["items"] as! [[String: Any]]
        #expect(items[0]["id"] as? Int == 1)
        #expect(items[1]["id"] as? Int == 2)
    }

    @Test func noOpForNonJsonInput() {
        let input = "not json at all"
        #expect(JqFilterService.deepParseJsonStrings(input) == input)
    }

    @Test func noOpForAlreadyParsedJson() {
        let input = #"{"a": {"b": 1}}"#
        let result = JqFilterService.deepParseJsonStrings(input)
        let parsed = try! JSONSerialization.jsonObject(with: result.data(using: .utf8)!) as! [String: Any]
        let a = parsed["a"] as! [String: Any]
        #expect(a["b"] as? Int == 1)
    }

    @Test func embeddedJsonArrayString() {
        let input = #"{"data": "[1, 2, 3]"}"#
        let result = JqFilterService.deepParseJsonStrings(input)
        let parsed = try! JSONSerialization.jsonObject(with: result.data(using: .utf8)!) as! [String: Any]
        let data = parsed["data"] as! [Int]
        #expect(data == [1, 2, 3])
    }

    @Test func emptyObject() {
        let input = "{}"
        let result = JqFilterService.deepParseJsonStrings(input)
        let parsed = try! JSONSerialization.jsonObject(with: result.data(using: .utf8)!) as! [String: Any]
        #expect(parsed.isEmpty)
    }

    @Test func enablesJqFilterOnEmbeddedJson() {
        let input = #"{"data": "{\"room_id\": \"general\", \"content\": \"Hello!\"}"}"#
        let preprocessed = JqFilterService.deepParseJsonStrings(input)
        let result = JqFilterService.evaluate(expression: ".data.content", json: preprocessed)
        if case .success(let text) = result {
            #expect(text == #""Hello!""#)
        } else {
            Issue.record("Expected .data.content to resolve after deep parsing")
        }
    }

    @Test func filterFailsWithoutDeepParse() {
        let input = #"{"data": "{\"room_id\": \"general\", \"content\": \"Hello!\"}"}"#
        let result = JqFilterService.evaluate(expression: ".data.content", json: input)
        if case .failure = result {
            // expected: .data is a string, can't access .content on it
        } else {
            Issue.record("Expected failure without deep parsing")
        }
    }

    // MARK: - Scalar coercion regression tests

    @Test func preservesStringThatLooksLikeNumber() {
        let input = #"{"version": "1.0"}"#
        let result = JqFilterService.deepParseJsonStrings(input)
        let parsed = try! JSONSerialization.jsonObject(with: result.data(using: .utf8)!) as! [String: Any]
        #expect(parsed["version"] as? String == "1.0", "String `1.0` must not be coerced to number")
        let filter = JqFilterService.evaluate(expression: #".version == "1.0""#, json: result)
        if case .success(let text) = filter {
            #expect(text == "true", "Equality check against string literal should match after deep parse")
        } else {
            Issue.record("Expected filter success")
        }
    }

    @Test func preservesStringThatLooksLikeBool() {
        let input = #"{"flag": "true"}"#
        let result = JqFilterService.deepParseJsonStrings(input)
        let parsed = try! JSONSerialization.jsonObject(with: result.data(using: .utf8)!) as! [String: Any]
        #expect(parsed["flag"] as? String == "true")
    }

    @Test func preservesStringThatLooksLikeNull() {
        let input = #"{"value": "null"}"#
        let result = JqFilterService.deepParseJsonStrings(input)
        let parsed = try! JSONSerialization.jsonObject(with: result.data(using: .utf8)!) as! [String: Any]
        #expect(parsed["value"] as? String == "null")
    }
}
