//
//  AutoHeaderServiceTests.swift
//  ReqeastTests
//

import Testing
@testable import Reqeast

@Suite("AutoHeaderService")
struct AutoHeaderServiceTests {
    @Test func hostFromSimpleUrl() {
        let data = HttpRequestData(url: "http://example.com")
        let headers = AutoHeaderService.generateHeaders(from: data)
        let host = headers.first { $0.key == "Host" }
        #expect(host?.value == "example.com")
    }

    @Test func hostWithPort() {
        let data = HttpRequestData(url: "http://example.com:8080")
        let headers = AutoHeaderService.generateHeaders(from: data)
        let host = headers.first { $0.key == "Host" }
        #expect(host?.value == "example.com:8080")
    }

    @Test func noHostForEmptyUrl() {
        let data = HttpRequestData(url: "")
        let headers = AutoHeaderService.generateHeaders(from: data)
        let host = headers.first { $0.key == "Host" }
        #expect(host == nil)
    }

    @Test func contentTypeJson() {
        let data = HttpRequestData(bodyType: .json)
        let headers = AutoHeaderService.generateHeaders(from: data)
        let ct = headers.first { $0.key == "Content-Type" }
        #expect(ct?.value == "application/json")
    }

    @Test func contentTypeUrlencoded() {
        let data = HttpRequestData(bodyType: .urlencoded)
        let headers = AutoHeaderService.generateHeaders(from: data)
        let ct = headers.first { $0.key == "Content-Type" }
        #expect(ct?.value == "application/x-www-form-urlencoded")
    }

    @Test func contentTypeRawHtml() {
        let data = HttpRequestData(bodyType: .raw, rawContentType: .html)
        let headers = AutoHeaderService.generateHeaders(from: data)
        let ct = headers.first { $0.key == "Content-Type" }
        #expect(ct?.value == "text/html")
    }

    @Test func contentTypeBinary() {
        let data = HttpRequestData(bodyType: .binary)
        let headers = AutoHeaderService.generateHeaders(from: data)
        let ct = headers.first { $0.key == "Content-Type" }
        #expect(ct?.value == "application/octet-stream")
    }

    @Test func noContentTypeForNone() {
        let data = HttpRequestData(bodyType: .none)
        let headers = AutoHeaderService.generateHeaders(from: data)
        let ct = headers.first { $0.key == "Content-Type" }
        #expect(ct == nil)
    }

    @Test func alwaysIncludesStandardHeaders() {
        let data = HttpRequestData()
        let headers = AutoHeaderService.generateHeaders(from: data)
        let keys = headers.map(\.key)
        #expect(keys.contains("User-Agent"))
        #expect(keys.contains("Accept"))
        #expect(keys.contains("Accept-Encoding"))
        #expect(keys.contains("Connection"))
    }
}
