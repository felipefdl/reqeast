//
//  CurlConverterBridgeTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("CurlConverterBridge", .serialized)
struct CurlConverterBridgeTests {

    @Test func parsesSimpleGet() throws {
        let result = try CurlConverterBridge.parse("curl https://example.com")
        #expect(result.url == "https://example.com")
        #expect(result.method == "get")
    }

    @Test func parsesCookiesFromBFlag() throws {
        let result = try CurlConverterBridge.parse("curl -b 'session=abc123; token=xyz' https://example.com")
        #expect(result.cookies?["session"] == "abc123")
        #expect(result.cookies?["token"] == "xyz")
    }

    @Test func parsesCookiesFromHeader() throws {
        let result = try CurlConverterBridge.parse("curl -H 'Cookie: session=abc123' https://example.com")
        #expect(result.cookies?["session"] == "abc123")
    }

    @Test func parsesQueryParamsWithUUIDs() throws {
        let result = try CurlConverterBridge.parse(
            "curl 'https://localhost:8080/analytics?recommendation_id=99aad996-a6f3-458a-81bc-827b1eeb692e&tenant_id=00000000-0000-4000-8000-000200001337'"
        )
        #expect(result.queries?["recommendation_id"] != nil)
        #expect(result.queries?["tenant_id"] != nil)
        if case .single(let val) = result.queries?["recommendation_id"] {
            #expect(val == "99aad996-a6f3-458a-81bc-827b1eeb692e")
        }
    }

    @Test func parsesAuth() throws {
        let result = try CurlConverterBridge.parse("curl -u admin:secret https://example.com")
        #expect(result.auth?.user == "admin")
        #expect(result.auth?.password == "secret")
    }

    @Test func parsesInsecureFlag() throws {
        let result = try CurlConverterBridge.parse("curl -k https://example.com")
        #expect(result.insecure != nil)
    }

    @Test func parsesHeaders() throws {
        let result = try CurlConverterBridge.parse(
            "curl -H 'Accept: application/json' -H 'X-Custom: value' https://example.com"
        )
        #expect(result.headers?["Accept"] == "application/json")
        #expect(result.headers?["X-Custom"] == "value")
    }

    @Test func parsesPostWithData() throws {
        let result = try CurlConverterBridge.parse(
            "curl -X POST -d '{\"key\":\"value\"}' https://example.com"
        )
        #expect(result.method == "post")
        #expect(result.data != nil)
    }

    @Test func parsesChromeDevToolsCurl() throws {
        let input = """
        curl 'https://api.example.com/data' \
          -H 'accept: application/json' \
          -H 'Cookie: session=abc123; csrf=token456' \
          --data-raw '{"key":"value"}' \
          --compressed
        """
        let result = try CurlConverterBridge.parse(input)
        #expect(result.url == "https://api.example.com/data")
        #expect(result.cookies?["session"] == "abc123")
        #expect(result.cookies?["csrf"] == "token456")
        #expect(result.headers?["accept"] == "application/json")
    }

    @Test func stripsQueryParamsFromUrl() throws {
        let result = try CurlConverterBridge.parse(
            "curl 'https://api.example.com/data?q=test&page=1'"
        )
        #expect(result.url == "https://api.example.com/data")
        #expect(result.rawUrl == "https://api.example.com/data?q=test&page=1")
    }
}
