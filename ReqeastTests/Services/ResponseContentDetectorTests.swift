//
//  ResponseContentDetectorTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("ResponseContentDetector")
struct ResponseContentDetectorTests {
    @Test func detectsJsonFromHeader() {
        let headers = [KeyValueEntry(key: "content-type", value: "application/json; charset=utf-8")]
        let body = "{}".data(using: .utf8)!
        let result = ResponseContentDetector.detect(headers: headers, body: body)
        if case .json = result {} else {
            Issue.record("Expected .json, got \(result)")
        }
    }

    @Test func detectsHtmlFromHeader() {
        let headers = [KeyValueEntry(key: "content-type", value: "text/html")]
        let body = "<html></html>".data(using: .utf8)!
        let result = ResponseContentDetector.detect(headers: headers, body: body)
        if case .html = result {} else {
            Issue.record("Expected .html, got \(result)")
        }
    }

    @Test func detectsXmlFromHeader() {
        let headers = [KeyValueEntry(key: "content-type", value: "application/xml")]
        let body = "<root/>".data(using: .utf8)!
        let result = ResponseContentDetector.detect(headers: headers, body: body)
        if case .xml = result {} else {
            Issue.record("Expected .xml, got \(result)")
        }
    }

    @Test func detectsImageFromHeader() {
        let headers = [KeyValueEntry(key: "content-type", value: "image/png")]
        let body = Data([0x89, 0x50, 0x4E, 0x47])
        let result = ResponseContentDetector.detect(headers: headers, body: body)
        if case .image(let subtype) = result {
            #expect(subtype == "png")
        } else {
            Issue.record("Expected .image, got \(result)")
        }
    }

    @Test func detectsJsonFromContent() {
        let headers: [KeyValueEntry] = []
        let body = "{\"key\": \"value\"}".data(using: .utf8)!
        let result = ResponseContentDetector.detect(headers: headers, body: body)
        if case .json = result {} else {
            Issue.record("Expected .json, got \(result)")
        }
    }

    @Test func detectsTextForPlainContent() {
        let headers: [KeyValueEntry] = []
        let body = "Hello world".data(using: .utf8)!
        let result = ResponseContentDetector.detect(headers: headers, body: body)
        if case .text = result {} else {
            Issue.record("Expected .text, got \(result)")
        }
    }

    @Test func detectsEmptyAsText() {
        let result = ResponseContentDetector.detect(headers: [], body: Data())
        if case .text = result {} else {
            Issue.record("Expected .text, got \(result)")
        }
    }
}
