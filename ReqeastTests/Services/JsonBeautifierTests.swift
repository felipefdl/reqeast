//
//  JsonBeautifierTests.swift
//  ReqeastTests
//

import Testing
@testable import Reqeast

@Suite("JsonBeautifier")
@MainActor
struct JsonBeautifierTests {
    @Test func prettifyValidJson() {
        let result = JsonBeautifier.prettify("{\"a\":1}", spaces: 2)
        #expect(result != nil)
        #expect(result?.contains("\n") == true)
        #expect(result?.contains("\"a\"") == true)
    }

    @Test func prettifyCustomSpaces() {
        let result = JsonBeautifier.prettify("{\"a\":1}", spaces: 4)
        #expect(result != nil)
        #expect(result?.contains("    \"a\"") == true)
    }

    @Test func prettifyInvalidJsonReturnsNil() {
        #expect(JsonBeautifier.prettify("{invalid}") == nil)
    }

    @Test func validateValidJson() {
        #expect(JsonBeautifier.validate("{\"key\":\"value\"}") == nil)
    }

    @Test func validateInvalidJson() {
        #expect(JsonBeautifier.validate("{invalid}") != nil)
    }

    @Test func validateEmptyReturnsNil() {
        #expect(JsonBeautifier.validate("") == nil)
        #expect(JsonBeautifier.validate("   ") == nil)
    }
}
