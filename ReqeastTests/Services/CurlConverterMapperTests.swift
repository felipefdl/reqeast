//
//  CurlConverterMapperTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("CurlConverterMapper")
struct CurlConverterMapperTests {

    @Test func mapsBasicFields() {
        let json = CurlConverterJSON(
            url: "https://example.com",
            rawUrl: "https://example.com",
            method: "get"
        )
        let result = CurlConverterMapper.map(json)
        #expect(result.data.method == "GET")
        #expect(result.data.url == "https://example.com")
        #expect(result.cookies.isEmpty)
    }

    @Test func mapsCookies() {
        let json = CurlConverterJSON(
            url: "https://example.com",
            rawUrl: "https://example.com",
            method: "get",
            cookies: ["session": "abc", "token": "xyz"]
        )
        let result = CurlConverterMapper.map(json)
        #expect(result.cookies["session"] == "abc")
        #expect(result.cookies["token"] == "xyz")
    }

    @Test func mapsQueryParams() {
        let json = CurlConverterJSON(
            url: "https://example.com",
            rawUrl: "https://example.com?q=test",
            method: "get",
            queries: ["q": .single("test"), "tags": .array(["a", "b"])]
        )
        let result = CurlConverterMapper.map(json)
        #expect(result.data.queryParams.count == 3) // q + tags[a] + tags[b]
        #expect(result.data.queryParams.contains { $0.name == "q" && $0.value == "test" })
        #expect(result.data.queryParams.contains { $0.name == "tags" && $0.value == "a" })
        #expect(result.data.queryParams.contains { $0.name == "tags" && $0.value == "b" })
    }

    @Test func mapsAuth() {
        let json = CurlConverterJSON(
            url: "https://example.com",
            rawUrl: "https://example.com",
            method: "get",
            auth: CurlAuth(user: "admin", password: "secret")
        )
        let result = CurlConverterMapper.map(json)
        #expect(result.data.basicAuthUser == "admin")
        #expect(result.data.basicAuthPassword == "secret")
    }

    @Test func mapsHeaders() {
        let json = CurlConverterJSON(
            url: "https://example.com",
            rawUrl: "https://example.com",
            method: "get",
            headers: ["Accept": "application/json"]
        )
        let result = CurlConverterMapper.map(json)
        #expect(result.data.headers.count == 1)
        #expect(result.data.headers[0].name == "Accept")
    }

    @Test func mapsInsecure() {
        let json = CurlConverterJSON(
            url: "https://example.com",
            rawUrl: "https://example.com",
            method: "get",
            insecure: false
        )
        let result = CurlConverterMapper.map(json)
        #expect(result.data.insecure)
    }

    @Test func mapsRawBody() {
        let json = CurlConverterJSON(
            url: "https://example.com",
            rawUrl: "https://example.com",
            method: "post",
            data: ["{\"key\":\"value\"}": ""]
        )
        let result = CurlConverterMapper.map(json)
        #expect(result.data.body == "{\"key\":\"value\"}")
    }

    @Test func mapsFormEncodedBody() {
        let json = CurlConverterJSON(
            url: "https://example.com",
            rawUrl: "https://example.com",
            method: "post",
            data: ["name": "John", "age": "30"]
        )
        let result = CurlConverterMapper.map(json)
        #expect(result.data.body?.contains("name=John") == true)
        #expect(result.data.body?.contains("age=30") == true)
    }
}
