//
//  HttpHeaderSuggestionsTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("HttpHeaderSuggestions")
struct HttpHeaderSuggestionsTests {
    @Test func prefixMatchingFiltersHeaders() {
        let results = HttpHeaderSuggestions.filterHeaders(matching: "Content")
        #expect(results.count == 5)
        #expect(results.allSatisfy { $0.name.contains("Content") })
    }

    @Test func caseInsensitiveMatchingWorks() {
        let results = HttpHeaderSuggestions.filterHeaders(matching: "content-ty")
        #expect(results.count == 1)
        #expect(results.first?.name == "Content-Type")
    }

    @Test func substringMatchingWorks() {
        let results = HttpHeaderSuggestions.filterHeaders(matching: "forward")
        #expect(results.contains { $0.name == "X-Forwarded-For" })
        #expect(results.contains { $0.name == "X-Forwarded-Host" })
        #expect(results.contains { $0.name == "X-Forwarded-Proto" })
        #expect(results.contains { $0.name == "Forwarded" })
    }

    @Test func emptyQueryReturnsNoHeaders() {
        let results = HttpHeaderSuggestions.filterHeaders(matching: "")
        #expect(results.isEmpty)
    }

    @Test func emptyValueQueryReturnsAllValuesForKnownHeader() {
        let results = HttpHeaderSuggestions.filterValues(forHeader: "Content-Type", matching: "")
        #expect(results.count == 15)
    }

    @Test func unknownHeaderReturnsNoValues() {
        let results = HttpHeaderSuggestions.filterValues(forHeader: "X-Custom-Header", matching: "")
        #expect(results.isEmpty)
    }

    @Test func valueFilteringIsCaseInsensitive() {
        let results = HttpHeaderSuggestions.filterValues(forHeader: "Content-Type", matching: "json")
        #expect(results.count == 2)
        #expect(results.contains("application/json"))
        #expect(results.contains("application/json; charset=utf-8"))
    }

    @Test func headerLookupIsCaseInsensitive() {
        let results = HttpHeaderSuggestions.filterValues(forHeader: "content-type", matching: "")
        #expect(results.count == 15)
    }

    @Test func exactHeaderMatchDismissesSuggestions() {
        #expect(HttpHeaderSuggestions.filterHeaders(matching: "Content-Type").isEmpty)
        #expect(HttpHeaderSuggestions.filterHeaders(matching: "content-type").isEmpty)
        #expect(HttpHeaderSuggestions.filterHeaders(matching: "ACCEPT").isEmpty)
    }

    @Test func exactValueMatchDismissesSuggestions() {
        #expect(HttpHeaderSuggestions.filterValues(forHeader: "Content-Type", matching: "application/json").isEmpty)
        #expect(HttpHeaderSuggestions.filterValues(forHeader: "DNT", matching: "1").isEmpty)
    }

    @Test func allHeadersHaveNonEmptyFields() {
        for header in HttpHeaderSuggestions.allHeaders {
            #expect(!header.name.isEmpty)
            #expect(!header.description.isEmpty)
        }
    }
}
