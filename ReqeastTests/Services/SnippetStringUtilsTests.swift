//
//  SnippetStringUtilsTests.swift
//  ReqeastTests
//

import Testing
@testable import Reqeast

@Suite("SnippetStringUtils")
struct SnippetStringUtilsTests {
    // MARK: - shellEscape

    @Test func shellEscapeEmpty() {
        #expect(SnippetStringUtils.shellEscape("") == "''")
    }

    @Test func shellEscapePlainString() {
        #expect(SnippetStringUtils.shellEscape("hello") == "'hello'")
    }

    @Test func shellEscapeSingleQuote() {
        #expect(SnippetStringUtils.shellEscape("it's") == "'it'\\''s'")
    }

    // MARK: - doubleQuoteEscape

    @Test func doubleQuoteEscapeBackslash() {
        #expect(SnippetStringUtils.doubleQuoteEscape("a\\b") == "a\\\\b")
    }

    @Test func doubleQuoteEscapeQuote() {
        #expect(SnippetStringUtils.doubleQuoteEscape("say \"hi\"") == "say \\\"hi\\\"")
    }

    @Test func doubleQuoteEscapeSpecialChars() {
        #expect(SnippetStringUtils.doubleQuoteEscape("\n") == "\\n")
        #expect(SnippetStringUtils.doubleQuoteEscape("\r") == "\\r")
        #expect(SnippetStringUtils.doubleQuoteEscape("\t") == "\\t")
    }

    // MARK: - indent

    @Test func indentSingleLine() {
        #expect(SnippetStringUtils.indent("hello", spaces: 4) == "    hello")
    }

    @Test func indentMultiLine() {
        let result = SnippetStringUtils.indent("a\nb", spaces: 2)
        #expect(result == "  a\n  b")
    }

    // MARK: - bodyContentDescription

    @Test func bodyContentDescriptionNone() {
        #expect(SnippetStringUtils.bodyContentDescription(.none) == "")
    }

    @Test func bodyContentDescriptionJson() {
        #expect(SnippetStringUtils.bodyContentDescription(.json("{\"k\":1}")) == "{\"k\":1}")
    }

    @Test func bodyContentDescriptionFormUrlencoded() {
        let body = ResolvedBody.formUrlencoded([("name", "val"), ("key", "val2")])
        #expect(SnippetStringUtils.bodyContentDescription(body) == "name=val&key=val2")
    }

    @Test func bodyContentDescriptionBinary() {
        #expect(SnippetStringUtils.bodyContentDescription(.binary(fileName: "file.bin")) == "[binary: file.bin]")
    }
}
