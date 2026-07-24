//
//  ImportRequestTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

// MARK: - ShellTokenizer

@Suite("ShellTokenizer")
struct ShellTokenizerTests {
    @Test func splitsSimpleTokens() {
        let tokens = ShellTokenizer.tokenize("curl -X GET https://example.com")
        #expect(tokens == ["curl", "-X", "GET", "https://example.com"])
    }

    @Test func handlesSingleQuotes() {
        let tokens = ShellTokenizer.tokenize("curl -H 'Content-Type: application/json' https://example.com")
        #expect(tokens == ["curl", "-H", "Content-Type: application/json", "https://example.com"])
    }

    @Test func handlesDoubleQuotes() {
        let tokens = ShellTokenizer.tokenize("curl -d \"hello world\" https://example.com")
        #expect(tokens == ["curl", "-d", "hello world", "https://example.com"])
    }

    @Test func handlesLineContinuations() {
        let input = "curl \\\n-X POST \\\nhttps://example.com"
        let tokens = ShellTokenizer.tokenize(input)
        #expect(tokens == ["curl", "-X", "POST", "https://example.com"])
    }

    @Test func handlesAnsiCQuoting() {
        let tokens = ShellTokenizer.tokenize("curl -d $'line1\\nline2' https://example.com")
        #expect(tokens == ["curl", "-d", "line1\nline2", "https://example.com"])
    }

    @Test func handlesBackslashEscapeInNormal() {
        let tokens = ShellTokenizer.tokenize("curl -H Authorization:\\ Bearer\\ token https://example.com")
        #expect(tokens == ["curl", "-H", "Authorization: Bearer token", "https://example.com"])
    }

    @Test func handlesEmptyInput() {
        let tokens = ShellTokenizer.tokenize("")
        #expect(tokens == [])
    }

    @Test func handlesDoubleQuoteEscapes() {
        let tokens = ShellTokenizer.tokenize("curl -d \"{\\\"key\\\": \\\"value\\\"}\" https://example.com")
        #expect(tokens == ["curl", "-d", "{\"key\": \"value\"}", "https://example.com"])
    }
}

// MARK: - WgetParser

@Suite("WgetParser")
struct WgetParserTests {
    @Test func parsesSimpleGet() throws {
        let tokens = ShellTokenizer.tokenize("wget https://example.com")
        let result = try WgetParser.parse(tokens)
        #expect(result.method == "GET")
        #expect(result.url == "https://example.com")
    }

    @Test func parsesMethodEqualsSyntax() throws {
        let tokens = ShellTokenizer.tokenize("wget --method=POST --body-data='{\"key\":\"value\"}' https://example.com")
        let result = try WgetParser.parse(tokens)
        #expect(result.method == "POST")
        #expect(result.body == "{\"key\":\"value\"}")
    }

    @Test func parsesMethodSpaceSyntax() throws {
        let tokens = ShellTokenizer.tokenize("wget --method POST --body-data '{\"key\":\"value\"}' https://example.com")
        let result = try WgetParser.parse(tokens)
        #expect(result.method == "POST")
    }

    @Test func parsesHeaders() throws {
        let tokens = ShellTokenizer.tokenize("wget --header='Content-Type: application/json' https://example.com")
        let result = try WgetParser.parse(tokens)
        #expect(result.headers.count == 1)
        #expect(result.headers[0].name == "Content-Type")
    }

    @Test func parsesAuth() throws {
        let tokens = ShellTokenizer.tokenize("wget --http-user=admin --http-password=secret https://example.com")
        let result = try WgetParser.parse(tokens)
        #expect(result.basicAuthUser == "admin")
        #expect(result.basicAuthPassword == "secret")
    }

    @Test func parsesInsecure() throws {
        let tokens = ShellTokenizer.tokenize("wget --no-check-certificate https://example.com")
        let result = try WgetParser.parse(tokens)
        #expect(result.insecure)
    }

    @Test func throwsOnNoUrl() throws {
        let tokens = ShellTokenizer.tokenize("wget --method=GET")
        #expect(throws: ImportError.self) {
            try WgetParser.parse(tokens)
        }
    }
}

// MARK: - HttpieParser

@Suite("HttpieParser")
struct HttpieParserTests {
    @Test func parsesSimpleGet() throws {
        let tokens = ShellTokenizer.tokenize("http https://example.com")
        let result = try HttpieParser.parse(tokens)
        #expect(result.method == "GET")
        #expect(result.url == "https://example.com")
    }

    @Test func parsesExplicitMethod() throws {
        let tokens = ShellTokenizer.tokenize("http DELETE https://api.example.com/1")
        let result = try HttpieParser.parse(tokens)
        #expect(result.method == "DELETE")
    }

    @Test func parsesHeaders() throws {
        let tokens = ShellTokenizer.tokenize("http https://example.com Content-Type:application/json Accept:text/html")
        let result = try HttpieParser.parse(tokens)
        #expect(result.headers.count == 2)
        #expect(result.headers[0].name == "Content-Type")
        #expect(result.headers[0].value == "application/json")
    }

    @Test func parsesQueryParams() throws {
        let tokens = ShellTokenizer.tokenize("http https://example.com q==test page==1")
        let result = try HttpieParser.parse(tokens)
        #expect(result.queryParams.count == 2)
        #expect(result.queryParams[0].name == "q")
        #expect(result.queryParams[0].value == "test")
    }

    @Test func parsesJsonFields() throws {
        let tokens = ShellTokenizer.tokenize("http POST https://example.com name=John age:=30")
        let result = try HttpieParser.parse(tokens)
        #expect(result.method == "POST")
        #expect(result.body != nil)
        #expect(result.body!.contains("\"name\": \"John\""))
        #expect(result.body!.contains("\"age\": 30"))
    }

    @Test func parsesAuth() throws {
        let tokens = ShellTokenizer.tokenize("http --auth user:pass https://example.com")
        let result = try HttpieParser.parse(tokens)
        #expect(result.basicAuthUser == "user")
        #expect(result.basicAuthPassword == "pass")
    }

    @Test func parsesFormMode() throws {
        let tokens = ShellTokenizer.tokenize("http --form POST https://example.com name=John")
        let result = try HttpieParser.parse(tokens)
        #expect(result.bodyIsForm)
        #expect(result.formFields.count == 1)
    }

    @Test func prependsSchemeIfMissing() throws {
        let tokens = ShellTokenizer.tokenize("http example.com/api")
        let result = try HttpieParser.parse(tokens)
        #expect(result.url == "http://example.com/api")
    }

    @Test func infersPostWithBody() throws {
        let tokens = ShellTokenizer.tokenize("http https://example.com key=value")
        let result = try HttpieParser.parse(tokens)
        #expect(result.method == "POST")
    }
}

// MARK: - ImportRequestService

@Suite("ImportRequestService")
struct ImportRequestServiceTests {
    @Test func detectsCurl() {
        #expect(ImportRequestService.detectFormat("curl https://example.com") == .curl)
    }

    @Test func detectsWget() {
        #expect(ImportRequestService.detectFormat("wget https://example.com") == .wget)
    }

    @Test func detectsHttpie() {
        #expect(ImportRequestService.detectFormat("http GET https://example.com") == .httpie)
        #expect(ImportRequestService.detectFormat("https example.com") == .httpie)
    }

    @Test func stripsShellPrompt() {
        #expect(ImportRequestService.detectFormat("$ curl https://example.com") == .curl)
        #expect(ImportRequestService.detectFormat("% wget https://example.com") == .wget)
    }

    @Test func returnsNilForUnknown() {
        #expect(ImportRequestService.detectFormat("unknown command") == nil)
    }

    @Test func throwsOnEmptyInput() {
        #expect(throws: ImportError.self) {
            try ImportRequestService.parse("")
        }
    }
}

// MARK: - ImportRequestMapper

@Suite("ImportRequestMapper")
struct ImportRequestMapperTests {
    @Test func mapsBasicGet() {
        var imported = ImportedRequestData()
        imported.method = "GET"
        imported.url = "https://api.example.com"
        let result = ImportRequestMapper.map(imported)
        #expect(result.method == .get)
        #expect(result.url == "https://api.example.com")
    }

    @Test func extractsQueryParamsFromUrl() {
        var imported = ImportedRequestData()
        imported.method = "GET"
        imported.url = "https://api.example.com?q=test&page=1"
        let result = ImportRequestMapper.map(imported)
        #expect(result.url == "https://api.example.com")
        // params include extracted + sentinel
        #expect(result.params.count == 3)
        #expect(result.params[0].key == "q")
        #expect(result.params[0].value == "test")
        #expect(result.params[1].key == "page")
        #expect(result.params[1].value == "1")
    }

    @Test func extractsBearerFromAuthHeader() {
        var imported = ImportedRequestData()
        imported.method = "GET"
        imported.url = "https://example.com"
        imported.headers = [(name: "Authorization", value: "Bearer mytoken123")]
        let result = ImportRequestMapper.map(imported)
        #expect(result.authType == .bearer)
        #expect(result.authToken == "mytoken123")
        // Authorization header should be removed
        #expect(result.headers.filter { !$0.isEmpty }.allSatisfy { $0.key.lowercased() != "authorization" })
    }

    @Test func mapsBasicAuth() {
        var imported = ImportedRequestData()
        imported.method = "GET"
        imported.url = "https://example.com"
        imported.basicAuthUser = "admin"
        imported.basicAuthPassword = "secret"
        let result = ImportRequestMapper.map(imported)
        #expect(result.authType == .basic)
        #expect(result.authUsername == "admin")
        #expect(result.authPassword == "secret")
    }

    @Test func mapsJsonBody() {
        var imported = ImportedRequestData()
        imported.method = "POST"
        imported.url = "https://example.com"
        imported.body = "{\"key\": \"value\"}"
        imported.headers = [(name: "Content-Type", value: "application/json")]
        let result = ImportRequestMapper.map(imported)
        #expect(result.bodyType == .json)
        #expect(result.bodyContent == "{\"key\": \"value\"}")
        // Content-Type should be removed
        #expect(result.headers.filter { !$0.isEmpty }.allSatisfy { $0.key.lowercased() != "content-type" })
    }

    @Test func mapsFormData() {
        var imported = ImportedRequestData()
        imported.method = "POST"
        imported.url = "https://example.com"
        imported.bodyIsForm = true
        imported.formFields = [(name: "name", value: "John"), (name: "age", value: "30")]
        let result = ImportRequestMapper.map(imported)
        #expect(result.bodyType == .formData)
        // formData includes entries + sentinel
        #expect(result.bodyFormData.count == 3)
        #expect(result.bodyFormData[0].key == "name")
        #expect(result.bodyFormData[0].value == "John")
    }

    @Test func mapsInsecureFlag() {
        var imported = ImportedRequestData()
        imported.method = "GET"
        imported.url = "https://example.com"
        imported.insecure = true
        let result = ImportRequestMapper.map(imported)
        #expect(result.sslVerify == false)
    }

    @Test func infersJsonFromBody() {
        var imported = ImportedRequestData()
        imported.method = "POST"
        imported.url = "https://example.com"
        imported.body = "{\"key\": \"value\"}"
        let result = ImportRequestMapper.map(imported)
        #expect(result.bodyType == .json)
    }

    @Test func appendsSentinelEntries() {
        var imported = ImportedRequestData()
        imported.method = "GET"
        imported.url = "https://example.com"
        let result = ImportRequestMapper.map(imported)
        // Last entry in params and headers should be empty sentinel
        #expect(result.params.last?.isEmpty == true)
        #expect(result.headers.last?.isEmpty == true)
    }

    @Test func fullCurlE2E() throws {
        let input = "curl -X POST 'https://api.example.com/data' -H 'Content-Type: application/json' -H 'Authorization: Bearer token123' -d '{\"key\": \"value\"}'"
        let importResult = try ImportRequestService.parse(input)
        let result = ImportRequestMapper.map(importResult.data)
        #expect(result.method == .post)
        #expect(result.url == "https://api.example.com/data")
        #expect(result.authType == .bearer)
        #expect(result.authToken == "token123")
        #expect(result.bodyType == .json)
        #expect(result.bodyContent == "{\"key\": \"value\"}")
    }

    @Test func curlCookieImportE2E() throws {
        let input = "curl -b 'session=abc123' https://example.com/api"
        let importResult = try ImportRequestService.parse(input)
        #expect(importResult.cookies["session"] == "abc123")
    }

    @Test func curlUuidQueryParamsE2E() throws {
        let input = "curl 'https://localhost:8080/analytics?recommendation_id=99aad996-a6f3-458a-81bc-827b1eeb692e&tenant_id=00000000-0000-4000-8000-000200001337'"
        let importResult = try ImportRequestService.parse(input)
        let result = ImportRequestMapper.map(importResult.data)
        #expect(result.params.contains { $0.key == "recommendation_id" && $0.value == "99aad996-a6f3-458a-81bc-827b1eeb692e" })
        #expect(result.params.contains { $0.key == "tenant_id" && $0.value == "00000000-0000-4000-8000-000200001337" })
    }

    @Test func extractsQueryParamsWithURLComponents() {
        var imported = ImportedRequestData()
        imported.method = "GET"
        imported.url = "https://api.example.com/search?q=hello+world&category=books&page=1"
        let result = ImportRequestMapper.map(imported)
        #expect(result.url == "https://api.example.com/search")
        #expect(result.params.contains { $0.key == "q" && $0.value == "hello+world" })
        #expect(result.params.contains { $0.key == "category" && $0.value == "books" })
        #expect(result.params.contains { $0.key == "page" && $0.value == "1" })
    }

    @Test func wgetStillReturnsParsedResult() throws {
        let result = try ImportRequestService.parse("wget https://example.com")
        #expect(result.data.method == "GET")
        #expect(result.data.url == "https://example.com")
        #expect(result.cookies.isEmpty)
    }

    @Test func httpieStillReturnsParsedResult() throws {
        let result = try ImportRequestService.parse("http GET https://example.com")
        #expect(result.data.method == "GET")
        #expect(result.data.url == "https://example.com")
        #expect(result.cookies.isEmpty)
    }
}
