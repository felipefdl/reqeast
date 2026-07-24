//
//  JqFilterPipelineTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("JqFilterService.filteredOutput")
struct JqFilterPipelineTests {

    @Test func invalidUtf8ReturnsNil() async {
        let invalid = Data([0xFF, 0xFE, 0xFD])
        let outcome = await JqFilterService.filteredOutput(body: invalid, expression: ".", unquote: false)
        #expect(outcome == nil)
    }

    @Test func successProducesDisplayText() async {
        let body = Data(#"{"name": "test"}"#.utf8)
        let outcome = await JqFilterService.filteredOutput(body: body, expression: ".name", unquote: false)
        guard case .success(let raw) = outcome?.result else {
            Issue.record("Expected success, got \(String(describing: outcome))")
            return
        }
        #expect(raw == "\"test\"")
        #expect(outcome?.display == "\"test\"")
    }

    @Test func unquoteStripsQuotesFromDisplay() async {
        let body = Data(#"{"name": "test"}"#.utf8)
        let outcome = await JqFilterService.filteredOutput(body: body, expression: ".name", unquote: true)
        #expect(outcome?.display == "test")
    }

    @Test func unquoteDeepParsesEmbeddedJson() async {
        let body = Data(#"{"data": "{\"inner\": 42}"}"#.utf8)
        let outcome = await JqFilterService.filteredOutput(body: body, expression: ".data.inner", unquote: true)
        #expect(outcome?.display == "42")
    }

    @Test func failureHasNoDisplayText() async {
        let body = Data(#"{"name": "test"}"#.utf8)
        let outcome = await JqFilterService.filteredOutput(body: body, expression: ".[broken", unquote: false)
        guard case .failure = outcome?.result else {
            Issue.record("Expected failure, got \(String(describing: outcome))")
            return
        }
        #expect(outcome?.display == nil)
    }
}
