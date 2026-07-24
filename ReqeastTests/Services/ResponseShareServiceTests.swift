//
//  ResponseShareServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("ResponseShareService")
struct ResponseShareServiceTests {
    private func makeResponse(
        statusCode: Int = 200,
        statusText: String = "OK",
        headers: [KeyValueEntry] = [],
        body: Data = Data(),
        elapsedMs: Double = 142,
        bodySize: Int64 = 0,
        finalUrl: String = "https://api.example.com/users",
        httpVersion: String = "HTTP/2",
        remoteAddr: String? = "93.184.216.34:443"
    ) -> HttpResponseData {
        HttpResponseData(
            statusCode: statusCode,
            statusText: statusText,
            headers: headers,
            body: body,
            elapsedMs: elapsedMs,
            bodySize: bodySize,
            finalUrl: finalUrl,
            timestamp: Date(timeIntervalSince1970: 0),
            cookies: [],
            httpVersion: httpVersion,
            remoteAddr: remoteAddr
        )
    }

    @Test func jsonResponseUsesJsonFence() {
        let headers = [KeyValueEntry(key: "content-type", value: "application/json")]
        let body = "{\"id\": 1}".data(using: .utf8)!
        let response = makeResponse(headers: headers, body: body, bodySize: Int64(body.count))
        let md = ResponseShareService.generateMarkdown(
            response: response, method: "GET", url: "https://example.com", requestName: nil
        )
        #expect(md.contains("```json"))
    }

    @Test func htmlResponseUsesHtmlFence() {
        let headers = [KeyValueEntry(key: "content-type", value: "text/html")]
        let body = "<html></html>".data(using: .utf8)!
        let response = makeResponse(headers: headers, body: body, bodySize: Int64(body.count))
        let md = ResponseShareService.generateMarkdown(
            response: response, method: "GET", url: "https://example.com", requestName: nil
        )
        #expect(md.contains("```html"))
    }

    @Test func emptyBodyShowsMessage() {
        let response = makeResponse()
        let md = ResponseShareService.generateMarkdown(
            response: response, method: "GET", url: "https://example.com", requestName: nil
        )
        #expect(md.contains("Empty body"))
    }

    @Test func binaryBodyShowsSize() {
        let body = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01])
        let response = makeResponse(body: body, bodySize: 131_584)
        let md = ResponseShareService.generateMarkdown(
            response: response, method: "GET", url: "https://example.com", requestName: nil
        )
        #expect(md.contains("Binary data"))
    }

    @Test func largeBodyIsTruncated() {
        let longText = String(repeating: "a", count: 15_000)
        let body = longText.data(using: .utf8)!
        let headers = [KeyValueEntry(key: "content-type", value: "text/plain")]
        let response = makeResponse(headers: headers, body: body, bodySize: Int64(body.count))
        let md = ResponseShareService.generateMarkdown(
            response: response, method: "GET", url: "https://example.com", requestName: nil
        )
        #expect(md.contains("Truncated at 10000 characters (15000 total)"))
    }

    @Test func redirectAddsFinalUrlLine() {
        let response = makeResponse(finalUrl: "https://example.com/redirected")
        let md = ResponseShareService.generateMarkdown(
            response: response, method: "GET", url: "https://example.com", requestName: nil
        )
        #expect(md.contains("Final URL: https://example.com/redirected"))
    }

    @Test func requestNameAppearsAsBlockquote() {
        let response = makeResponse()
        let md = ResponseShareService.generateMarkdown(
            response: response, method: "GET", url: "https://example.com", requestName: "My API Request"
        )
        #expect(md.contains("> My API Request"))
    }

    @Test func noRequestNameOmitsBlockquote() {
        let response = makeResponse()
        let md = ResponseShareService.generateMarkdown(
            response: response, method: "GET", url: "https://example.com", requestName: nil
        )
        #expect(!md.contains("> "))
    }

    @Test func versionHeaderPresent() {
        let response = makeResponse()
        let md = ResponseShareService.generateMarkdown(
            response: response, method: "GET", url: "https://example.com", requestName: nil
        )
        #expect(md.hasPrefix("# Reqeast/v"))
    }

    @Test func remoteAddrOmittedWhenNil() {
        let response = makeResponse(remoteAddr: nil)
        let md = ResponseShareService.generateMarkdown(
            response: response, method: "GET", url: "https://example.com", requestName: nil
        )
        #expect(!md.contains("- Remote:"))
    }
}
