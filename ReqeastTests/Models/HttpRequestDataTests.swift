//
//  HttpRequestDataTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("HttpRequestData")
struct HttpRequestDataTests {

    // MARK: - Default Init

    @Test func defaultInitValues() {
        let data = HttpRequestData()
        #expect(data.method == .get)
        #expect(data.url == "")
        #expect(data.bodyType == .none)
        #expect(data.rawContentType == .text)
        #expect(data.followRedirects == true)
        #expect(data.timeoutSeconds == 30)
        #expect(data.sslVerify == true)
        #expect(data.maxRedirects == 10)
        #expect(data.httpVersion == "auto")
        #expect(data.encodeUrl == true)
        #expect(data.disabledAutoHeaders.isEmpty)
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTripWithNonDefaults() throws {
        var data = HttpRequestData()
        data.method = .post
        data.url = "https://example.com"
        data.bodyType = .json
        data.bodyContent = "{\"key\":\"value\"}"
        data.followRedirects = false
        data.timeoutSeconds = 60
        data.sslVerify = false
        data.maxRedirects = 5
        data.httpVersion = "http2"

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(HttpRequestData.self, from: encoded)

        #expect(decoded.method == .post)
        #expect(decoded.url == "https://example.com")
        #expect(decoded.bodyType == .json)
        #expect(decoded.bodyContent == "{\"key\":\"value\"}")
        #expect(decoded.followRedirects == false)
        #expect(decoded.timeoutSeconds == 60)
        #expect(decoded.sslVerify == false)
        #expect(decoded.maxRedirects == 5)
        #expect(decoded.httpVersion == "http2")
    }

    // MARK: - Backward Compatibility

    @Test func decodeMissingRawContentTypeDefaultsToText() throws {
        let json = minimalJson()
        let data = try JSONDecoder().decode(HttpRequestData.self, from: json)
        #expect(data.rawContentType == .text)
    }

    @Test func decodeMissingBinaryFileNameDefaultsToEmpty() throws {
        let json = minimalJson()
        let data = try JSONDecoder().decode(HttpRequestData.self, from: json)
        #expect(data.binaryFileName == "")
    }

    @Test func decodeMissingSslVerifyDefaultsToTrue() throws {
        let json = minimalJson()
        let data = try JSONDecoder().decode(HttpRequestData.self, from: json)
        #expect(data.sslVerify == true)
    }

    @Test func decodeMissingHttpVersionDefaultsToAuto() throws {
        let json = minimalJson()
        let data = try JSONDecoder().decode(HttpRequestData.self, from: json)
        #expect(data.httpVersion == "auto")
    }

    @Test func decodeMissingMaxRedirectsDefaultsTo10() throws {
        let json = minimalJson()
        let data = try JSONDecoder().decode(HttpRequestData.self, from: json)
        #expect(data.maxRedirects == 10)
    }

    @Test func decodeMissingDisabledAutoHeadersDefaultsToEmpty() throws {
        let json = minimalJson()
        let data = try JSONDecoder().decode(HttpRequestData.self, from: json)
        #expect(data.disabledAutoHeaders.isEmpty)
    }

    @Test func decodeMissingOAuth2FieldsDefaultsToEmpty() throws {
        let json = minimalJson()
        let data = try JSONDecoder().decode(HttpRequestData.self, from: json)
        #expect(data.authOAuth2GrantType == "")
        #expect(data.authOAuth2AuthURL == "")
        #expect(data.authOAuth2TokenURL == "")
        #expect(data.authOAuth2Scopes == "")
    }

    // MARK: - KeyValueEntry

    @Test func keyValueEntryIsEmptyWhenBothEmpty() {
        let entry = KeyValueEntry(key: "", value: "")
        #expect(entry.isEmpty == true)
    }

    @Test func keyValueEntryIsNotEmptyWhenKeyPresent() {
        let entry = KeyValueEntry(key: "Content-Type", value: "")
        #expect(entry.isEmpty == false)
    }

    // MARK: - Helpers

    /// Minimal JSON with only the required fields (no optional backward-compat fields).
    private func minimalJson() -> Data {
        let json = """
        {
            "method": "GET",
            "url": "",
            "params": [],
            "headers": [],
            "bodyType": "none",
            "bodyContent": "",
            "bodyFormData": [],
            "authType": "none",
            "authToken": "",
            "authUsername": "",
            "authPassword": "",
            "authApiKeyName": "",
            "authApiKeyValue": "",
            "authApiKeyLocation": "header",
            "followRedirects": true,
            "timeoutSeconds": 30
        }
        """
        return Data(json.utf8)
    }
}
