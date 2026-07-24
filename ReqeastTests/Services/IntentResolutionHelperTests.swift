//
//  IntentResolutionHelperTests.swift
//  ReqeastTests
//

@testable import Reqeast
import Testing

@Suite("IntentResolutionHelper.parseVariableOverrides")
struct IntentResolutionHelperTests {

    @Test func nilInputReturnsEmptyDict() {
        let result = IntentResolutionHelper.parseVariableOverrides(nil)
        #expect(result.isEmpty)
    }

    @Test func emptyStringReturnsEmptyDict() {
        let result = IntentResolutionHelper.parseVariableOverrides("")
        #expect(result.isEmpty)
    }

    @Test func singleKeyValuePair() {
        let result = IntentResolutionHelper.parseVariableOverrides("KEY=VALUE")
        #expect(result == ["KEY": "VALUE"])
    }

    @Test func multipleLines() {
        let result = IntentResolutionHelper.parseVariableOverrides("A=1\nB=2")
        #expect(result == ["A": "1", "B": "2"])
    }

    @Test func whitespaceIsTrimmed() {
        let result = IntentResolutionHelper.parseVariableOverrides(" KEY = VALUE ")
        #expect(result == ["KEY": "VALUE"])
    }

    @Test func linesWithoutEqualsSkipped() {
        let result = IntentResolutionHelper.parseVariableOverrides("GOOD=val\nNOEQUALS\nALSO=ok")
        #expect(result == ["GOOD": "val", "ALSO": "ok"])
    }
}
