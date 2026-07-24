//
//  ResponseEditorIdentityTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("ResponseEditorIdentity")
struct ResponseEditorIdentityTests {
  private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

  @Test func sameInputsProduceSameId() {
    let a = ResponseEditorIdentity.id(timestamp: timestamp, text: "{\"a\":1}")
    let b = ResponseEditorIdentity.id(timestamp: timestamp, text: "{\"a\":1}")
    #expect(a == b)
  }

  @Test func differentTextChangesIdForSameResponse() {
    // Regression: jq filter mutates text but timestamp stays the same.
    // If the id ignored text, the editor would never rebuild on filter change.
    let filtered = ResponseEditorIdentity.id(timestamp: timestamp, text: ".data result")
    let reFiltered = ResponseEditorIdentity.id(timestamp: timestamp, text: ".meta result")
    #expect(filtered != reFiltered)
  }

  @Test func differentTimestampChangesIdForSameText() {
    // Regression: two responses with identical bodies must still rebuild the editor,
    // otherwise a re-send with unchanged content would not reset editor state.
    let text = "{\"a\":1}"
    let first = ResponseEditorIdentity.id(timestamp: timestamp, text: text)
    let second = ResponseEditorIdentity.id(timestamp: timestamp.addingTimeInterval(1), text: text)
    #expect(first != second)
  }

  @Test func sameLengthDifferentContentChangesId() {
    // Regression: the earlier .id(text.count) keyed on count alone, so two same-length
    // responses would collide. Hashing the full text avoids that.
    let a = ResponseEditorIdentity.id(timestamp: timestamp, text: "abcdef")
    let b = ResponseEditorIdentity.id(timestamp: timestamp, text: "ghijkl")
    #expect(a != b)
  }

  @Test func embedsTimestampLiterally() {
    let id = ResponseEditorIdentity.id(timestamp: timestamp, text: "x")
    #expect(id.hasPrefix("1700000000.0-"))
  }
}
