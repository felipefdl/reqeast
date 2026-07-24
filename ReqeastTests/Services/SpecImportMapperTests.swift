//
//  SpecImportMapperTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("SpecImportMapper")
struct SpecImportMapperTests {

    static let fixturesDirectory: URL = {
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            return URL(fileURLWithPath: srcRoot, isDirectory: true)
                .appendingPathComponent("ReqeastTests/Fixtures/SpecImport", isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SpecImport", isDirectory: true)
    }()

    struct GoldenFixtureOptions {
        var folderStrategy: SpecFolderStrategy = .tags
    }

    struct GoldenCase: Sendable {
        let name: String
        var options: GoldenFixtureOptions = GoldenFixtureOptions()
    }

    static let goldenCases: [GoldenCase] = [
        GoldenCase(name: "petstore-2.0"),
        GoldenCase(name: "petstore-3.0"),
        GoldenCase(name: "petstore-3.1"),
        GoldenCase(name: "stripe-like"),
        GoldenCase(name: "servers-multi"),
        GoldenCase(name: "auth-schemes"),
        GoldenCase(name: "folder-tags"),
        GoldenCase(name: "folder-paths", options: GoldenFixtureOptions(folderStrategy: .paths)),
        GoldenCase(name: "folder-flat", options: GoldenFixtureOptions(folderStrategy: .flat)),
        GoldenCase(name: "postman-nested"),
        GoldenCase(name: "postman-vars"),
        GoldenCase(name: "har-capture"),
        GoldenCase(name: "asyncapi-http"),
        GoldenCase(name: "asyncapi-ws"),
        GoldenCase(name: "graphql-simple"),
    ]

    // MARK: - Golden parity

    @Test(arguments: goldenCases)
    func projectGoldenParity(testCase: GoldenCase) throws {
        let parsed = try parseFixture(named: testCase.name)
        let mapped = mapFixture(parsed, name: testCase.name, options: testCase.options)
        let actual = SpecImportProjectGolden(from: mapped)

        let goldenURL = Self.fixturesDirectory.appendingPathComponent("\(testCase.name).project.json")
        let expectedData = try Data(contentsOf: goldenURL)
        let expected = try JSONDecoder().decode(SpecImportProjectGolden.self, from: expectedData)
        #expect(actual == expected, "Golden mismatch for \(testCase.name)")
    }

    // MARK: - AC2 base_url

    @Test func petstore31YamlCreatesBaseURLEnvironment() throws {
        let parsed = try parseFixture(named: "petstore-3.1", preferJSON: false)
        let mapped = mapFixture(parsed, name: "petstore-3.1")

        #expect(mapped.environments.count == 1)
        #expect(mapped.environments[0].variables.contains { $0.key == "base_url" && $0.value == "https://petstore31.example.test/v1" })
        #expect(mapped.requests.allSatisfy { $0.httpData?.url.hasPrefix("{{base_url}}") == true })
    }

    @Test func petstore31JsonCreatesBaseURLEnvironment() throws {
        let parsed = try parseFixture(named: "petstore-3.1", preferJSON: true)
        let mapped = mapFixture(parsed, name: "petstore-3.1")

        #expect(mapped.environments.count == 1)
        #expect(mapped.environments[0].variables.contains { $0.key == "base_url" })
    }

    // MARK: - AC22 GraphQL mapper parity

    @Test func graphqlSimpleAC22GoldenParity() throws {
        let parsed = try parseFixture(named: "graphql-simple")
        let mapped = mapFixture(parsed, name: "graphql-simple")
        let actual = SpecImportProjectGolden(from: mapped)

        let goldenURL = Self.fixturesDirectory.appendingPathComponent("graphql-simple.project.json")
        let expectedData = try Data(contentsOf: goldenURL)
        let expected = try JSONDecoder().decode(SpecImportProjectGolden.self, from: expectedData)
        #expect(actual == expected)

        let userRequest = try #require(mapped.requests.first { $0.specIdentity?.primaryKey == "query user" })
        let httpData = try #require(userRequest.httpData)
        #expect(httpData.method == .post)
        #expect(httpData.url == "{{base_url}}")
        #expect(httpData.bodyType == .json)
        #expect(httpData.params.contains { $0.key == "id" })
        #expect(httpData.bodyContent.contains("\"query\""))
        #expect(httpData.bodyContent.contains("\"variables\""))
        #expect(httpData.headers.contains { $0.key == "Content-Type" && $0.value == "application/json" })
    }

    // MARK: - AC24 AsyncAPI mapper parity

    @Test func asyncapiHttpAC24GoldenParity() throws {
        let parsed = try parseFixture(named: "asyncapi-http")
        let mapped = mapFixture(parsed, name: "asyncapi-http")
        let actual = SpecImportProjectGolden(from: mapped)

        let goldenURL = Self.fixturesDirectory.appendingPathComponent("asyncapi-http.project.json")
        let expectedData = try Data(contentsOf: goldenURL)
        let expected = try JSONDecoder().decode(SpecImportProjectGolden.self, from: expectedData)
        #expect(actual == expected)

        #expect(mapped.requests.count == 2)
        #expect(mapped.warnings.filter { $0.code == "UNSUPPORTED_BINDING" }.count == 2)

        let createUser = try #require(mapped.requests.first { $0.specIdentity?.primaryKey == "createUser" })
        let httpData = try #require(createUser.httpData)
        #expect(httpData.method == .post)
        #expect(httpData.bodyType == .json)
        #expect(httpData.bodyContent.contains("Ada"))
    }

    @Test func asyncapiWsMapsWebSocketRequests() throws {
        let parsed = try parseFixture(named: "asyncapi-ws")
        let mapped = mapFixture(parsed, name: "asyncapi-ws")
        let actual = SpecImportProjectGolden(from: mapped)

        let goldenURL = Self.fixturesDirectory.appendingPathComponent("asyncapi-ws.project.json")
        let expectedData = try Data(contentsOf: goldenURL)
        let expected = try JSONDecoder().decode(SpecImportProjectGolden.self, from: expectedData)
        #expect(actual == expected)

        let sendMessage = try #require(mapped.requests.first { $0.specIdentity?.primaryKey == "sendChatMessage" })
        #expect(sendMessage.type == .webSocket)
        let wsData = try #require(sendMessage.webSocketData)
        #expect(wsData.url == "{{ws_url}}/chat")
        #expect(wsData.messageHistory.count == 1)
        #expect(wsData.messageHistory[0].text.contains("hello"))
        #expect(mapped.environments[0].variables.contains { $0.key == "ws_url" })
    }

    // MARK: - AC3 Postman mapper parity

    @Test func postmanVarsMapsCollectionApiKeyAuth() throws {
        let parsed = try parseFixture(named: "postman-vars")
        let mapped = mapFixture(parsed, name: "postman-vars")

        #expect(mapped.requests.allSatisfy { $0.httpData?.authType == .apiKey })
        #expect(mapped.requests.allSatisfy { $0.httpData?.authApiKeyName == "X-API-Key" })
        #expect(mapped.requests.allSatisfy { $0.httpData?.authApiKeyValue == "{{api_key}}" })
        #expect(mapped.requests.allSatisfy { $0.httpData?.authApiKeyLocation == "header" })
    }

    @Test func postmanNestedMapsRawJsonBody() throws {
        let parsed = try parseFixture(named: "postman-nested")
        let mapped = mapFixture(parsed, name: "postman-nested")

        let createUser = try #require(mapped.requests.first { $0.specIdentity?.primaryKey == "POST /users" })
        let httpData = try #require(createUser.httpData)

        #expect(httpData.bodyType == .json)
        #expect(httpData.bodyContent == "{\n  \"name\": \"Ada\"\n}")
    }

    @Test func postmanBodyModesMapUrlencodedAndFormData() throws {
        let urlencodedOp = NormalizedOperation(
            primaryKey: "POST /submit",
            alternateKeys: [],
            name: "Submit",
            method: "POST",
            path: "/submit",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .urlencoded(fields: [
                NormalizedKeyValue(key: "name", value: "Ada", enabled: true),
                NormalizedKeyValue(key: "role", value: "admin", enabled: true),
            ]),
            bodyCandidates: [],
            auth: nil,
            description: nil
        )
        let formDataOp = NormalizedOperation(
            primaryKey: "POST /upload",
            alternateKeys: [],
            name: "Upload",
            method: "POST",
            path: "/upload",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .formData(entries: [
                NormalizedFormDataEntry(
                    key: "note",
                    value: "hello",
                    isFile: false,
                    fileName: nil,
                    contentType: nil
                ),
                NormalizedFormDataEntry(
                    key: "avatar",
                    value: "/path/to/avatar.png",
                    isFile: true,
                    fileName: "avatar.png",
                    contentType: "image/png"
                ),
            ]),
            bodyCandidates: [],
            auth: nil,
            description: nil
        )
        let project = NormalizedProject(
            title: "Body Modes",
            description: nil,
            version: nil,
            iconUrl: nil,
            securitySchemes: [],
            folders: [],
            operations: [urlencodedOp, formDataOp],
            environments: []
        )
        let result = SpecImportResult(
            project: project,
            warnings: [],
            contentFingerprint: "test"
        )

        let mapped = SpecImportMapper.map(
            result,
            projectId: projectId(for: "postman-body-modes"),
            idContext: idContext(for: "postman-body-modes")
        )

        let submit = try #require(mapped.requests.first { $0.specIdentity?.primaryKey == "POST /submit" })
        let submitData = try #require(submit.httpData)
        #expect(submitData.bodyType == .urlencoded)
        #expect(submitData.bodyFormData.count == 2)
        #expect(submitData.bodyFormData.contains { $0.key == "name" && $0.value == "Ada" })

        let upload = try #require(mapped.requests.first { $0.specIdentity?.primaryKey == "POST /upload" })
        let uploadData = try #require(upload.httpData)
        #expect(uploadData.bodyType == .formData)
        #expect(uploadData.bodyFormDataEntries.count == 2)
        #expect(uploadData.bodyFormDataEntries.contains { $0.key == "note" && $0.fieldType == .text })
        #expect(uploadData.bodyFormDataEntries.contains { $0.key == "avatar" && $0.fieldType == .file })
    }

    @Test func postmanNestedPassesThroughResponseNotImportedWarning() throws {
        let parsed = try parseFixture(named: "postman-nested")
        let mapped = mapFixture(parsed, name: "postman-nested")

        #expect(mapped.warnings.contains {
            $0.code == "RESPONSE_NOT_IMPORTED"
                && $0.message == "Postman response examples are not imported"
                && $0.operationRef == "GET /users"
        })
    }

    // MARK: - AC13 stripe-like urlencoded

    @Test func stripeLikeMapsUrlencodedBody() throws {
        let parsed = try parseFixture(named: "stripe-like")
        let mapped = mapFixture(parsed, name: "stripe-like")

        let createCharge = try #require(mapped.requests.first { $0.specIdentity?.primaryKey == "createCharge" })
        let httpData = try #require(createCharge.httpData)

        #expect(httpData.bodyType == .urlencoded)
        #expect(httpData.bodyFormData.count == 2)
        #expect(httpData.bodyFormData.contains { $0.key == "amount" && $0.value == "2000" })
        #expect(httpData.bodyFormData.contains { $0.key == "currency" && $0.value == "usd" })
    }

    // MARK: - AC15 folder strategies

    @Test func folderPathsStrategyCreatesPathFolders() throws {
        let parsed = try parseFixture(named: "folder-paths")
        var options = SpecImportOptions.default
        options.folderStrategy = .paths
        let mapped = SpecImportMapper.map(
            parsed,
            projectId: projectId(for: "folder-paths"),
            options: options,
            idContext: idContext(for: "folder-paths")
        )

        #expect(mapped.folders.map(\.name).sorted() == [
            "api/v1/billing/invoices",
            "api/v1/billing/invoices/payments",
            "api/v1/users",
        ])
        #expect(mapped.requests.count == 4)
    }

    @Test func folderFlatStrategyHasNoFolders() throws {
        let parsed = try parseFixture(named: "folder-flat")
        var options = SpecImportOptions.default
        options.folderStrategy = .flat
        let mapped = SpecImportMapper.map(
            parsed,
            projectId: projectId(for: "folder-flat"),
            options: options,
            idContext: idContext(for: "folder-flat")
        )

        #expect(mapped.folders.isEmpty)
        #expect(mapped.requests.allSatisfy { $0.folderId == nil })
    }

    // MARK: - AC15 skip oversized operations

    @Test func skipsOperationsOverRecordLimit() throws {
        let hugeBody = String(repeating: "x", count: 950_000)
        let operation = NormalizedOperation(
            primaryKey: "hugeOp",
            alternateKeys: [],
            name: "Huge",
            method: "POST",
            path: "/huge",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .json(content: hugeBody),
            bodyCandidates: [],
            auth: nil,
            description: nil
        )
        let project = NormalizedProject(
            title: "Huge",
            description: nil,
            version: nil,
            iconUrl: nil,
            securitySchemes: [],
            folders: [],
            operations: [operation],
            environments: []
        )
        let result = SpecImportResult(
            project: project,
            warnings: [],
            contentFingerprint: "test"
        )

        let mapped = SpecImportMapper.map(result, projectId: UUID())

        #expect(mapped.requests.isEmpty)
        #expect(mapped.warnings.contains { $0.code == "RECORD_TOO_LARGE" })
    }

    // MARK: - Options

    @Test func authSchemesMapsOAuth2Scaffold() throws {
        let parsed = try parseFixture(named: "auth-schemes")
        let mapped = mapFixture(parsed, name: "auth-schemes")

        let oauth = try #require(mapped.requests.first { $0.specIdentity?.primaryKey == "postOAuth" })
        let httpData = try #require(oauth.httpData)

        #expect(httpData.authType == .oauth2)
        #expect(httpData.authToken == "{{token}}")
        #expect(httpData.authOAuth2GrantType == OAuth2GrantType.clientCredentials.rawValue)
        #expect(httpData.authOAuth2AuthURL == "")
        #expect(httpData.authOAuth2TokenURL == "https://auth.example.test/oauth/token")
        #expect(httpData.authOAuth2Scopes == "write")
    }

    @Test func scaffoldAuthCanBeDisabled() throws {
        let parsed = try parseFixture(named: "auth-schemes")
        var options = SpecImportOptions.default
        options.scaffoldAuth = false
        let mapped = SpecImportMapper.map(
            parsed,
            projectId: projectId(for: "auth-schemes"),
            options: options,
            idContext: idContext(for: "auth-schemes")
        )

        let protected = try #require(mapped.requests.first { $0.specIdentity?.primaryKey == "getProtected" })
        let httpData = try #require(protected.httpData)
        #expect(httpData.authType == .none)
        #expect(httpData.authToken.isEmpty)
    }

    @Test func preferredBodyContentTypeSelectsXmlOverFirstListed() throws {
        let operation = NormalizedOperation(
            primaryKey: "createPet",
            alternateKeys: [],
            name: "Create pet",
            method: "POST",
            path: "/pets",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .json(content: "{\n  \"name\": \"Fluffy\"\n}"),
            bodyCandidates: [
                NormalizedBodyCandidate(
                    contentType: "application/json",
                    body: .json(content: "{\n  \"name\": \"Fluffy\"\n}")
                ),
                NormalizedBodyCandidate(
                    contentType: "application/xml",
                    body: .raw(content: "<pet/>", contentType: "application/xml")
                ),
            ],
            auth: nil,
            description: nil
        )
        let project = NormalizedProject(
            title: "Multi Body",
            description: nil,
            version: nil,
            iconUrl: nil,
            securitySchemes: [],
            folders: [],
            operations: [operation],
            environments: []
        )
        let result = SpecImportResult(
            project: project,
            warnings: [],
            contentFingerprint: "test"
        )

        var options = SpecImportOptions.default
        options.preferredBodyContentType = .xml
        let mapped = SpecImportMapper.map(result, projectId: UUID(), options: options)

        let request = try #require(mapped.requests.first)
        let httpData = try #require(request.httpData)
        #expect(httpData.bodyType == .raw)
        #expect(httpData.bodyContent == "<pet/>")
        #expect(httpData.rawContentType == .xml)
        #expect(mapped.warnings.contains {
            $0.code == "MULTIPLE_CONTENT_TYPES"
                && ($0.message.contains("preferred") || $0.message.contains("application/xml"))
        })
    }

    @Test func schemaSynthesisEmitsWarningsForSynthesizedParameters() throws {
        let operation = NormalizedOperation(
            primaryKey: "listPets",
            alternateKeys: [],
            name: "List pets",
            method: "GET",
            path: "/pets",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [
                NormalizedParameter(
                    location: .query,
                    name: "limit",
                    value: "0",
                    required: false,
                    enabled: false,
                    valueSource: .synthesized
                ),
            ],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )
        let project = NormalizedProject(
            title: "Synthesis",
            description: nil,
            version: nil,
            iconUrl: nil,
            securitySchemes: [],
            folders: [],
            operations: [operation],
            environments: []
        )
        let result = SpecImportResult(
            project: project,
            warnings: [],
            contentFingerprint: "test"
        )

        var options = SpecImportOptions.default
        options.enableSchemaSynthesis = true
        let mapped = SpecImportMapper.map(result, projectId: UUID(), options: options)

        #expect(mapped.warnings.contains {
            $0.code == "SYNTHESIZED_VALUE"
                && $0.message.contains("limit")
                && $0.operationRef == "get /pets"
        })
    }

    @Test func schemaSynthesisDisabledSkipsSynthesizedParameterWarnings() throws {
        let operation = NormalizedOperation(
            primaryKey: "listPets",
            alternateKeys: [],
            name: "List pets",
            method: "GET",
            path: "/pets",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [
                NormalizedParameter(
                    location: .query,
                    name: "limit",
                    value: "0",
                    required: false,
                    enabled: false,
                    valueSource: .synthesized
                ),
            ],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )
        let project = NormalizedProject(
            title: "Synthesis",
            description: nil,
            version: nil,
            iconUrl: nil,
            securitySchemes: [],
            folders: [],
            operations: [operation],
            environments: []
        )
        let result = SpecImportResult(
            project: project,
            warnings: [],
            contentFingerprint: "test"
        )

        let mapped = SpecImportMapper.map(result, projectId: UUID())

        #expect(!mapped.warnings.contains { $0.code == "SYNTHESIZED_VALUE" })
    }

    // MARK: - AC23 HAR mapper parity

    @Test func harCaptureStripsCredentialsAndWarns() throws {
        let parsed = try parseFixture(named: "har-capture")
        let mapped = mapFixture(parsed, name: "har-capture")

        #expect(parsed.warnings.contains { $0.code == "HAR_CREDENTIALS_STRIPPED" })
        let listPets = try #require(mapped.requests.first { $0.specIdentity?.primaryKey == "GET /pets" })
        let httpData = try #require(listPets.httpData)
        #expect(!httpData.headers.contains { $0.key.lowercased() == "cookie" })
        #expect(!httpData.headers.contains { $0.key.lowercased() == "authorization" })
        #expect(httpData.headers.contains { $0.key == "Accept" && $0.value == "application/json" })
    }

    @Test func harCaptureImportsCredentialPlaceholdersWhenEnabled() throws {
        let parsed = try parseHarFixture(
            named: "har-capture",
            importHarCredentialsAsPlaceholders: true
        )
        let mapped = mapFixture(
            parsed,
            name: "har-capture",
            options: GoldenFixtureOptions(),
            importHarCredentialsAsPlaceholders: true
        )

        let listPets = try #require(mapped.requests.first { $0.specIdentity?.primaryKey == "GET /pets" })
        let httpData = try #require(listPets.httpData)
        #expect(httpData.headers.contains { $0.key == "Cookie" && $0.value == "{{cookie}}" })
        #expect(httpData.headers.contains { $0.key == "Authorization" && $0.value == "Bearer {{token}}" })
        #expect(httpData.authType == .bearer)
        #expect(httpData.authToken == "{{token}}")
    }

    @Test func createEnvironmentsCanBeDisabled() throws {
        let parsed = try parseFixture(named: "petstore-3.1")
        var options = SpecImportOptions.default
        options.createEnvironments = false
        let mapped = SpecImportMapper.map(
            parsed,
            projectId: projectId(for: "petstore-3.1"),
            options: options,
            idContext: idContext(for: "petstore-3.1")
        )

        #expect(mapped.environments.isEmpty)
    }

    // MARK: - Helpers

    private func parseFixture(named name: String, preferJSON: Bool = false) throws -> SpecImportResult {
        let url = try fixtureInputURL(named: name, preferJSON: preferJSON)
        let hint = sourceHint(for: url)
        let data = try Data(contentsOf: url)
        return try parseSpec(
            bytes: data,
            sourceHint: hint,
            bundleEntryPath: nil,
            options: SpecParseOptions(enableSchemaSynthesis: false)
        )
    }

    private func parseHarFixture(
        named name: String,
        importHarCredentialsAsPlaceholders: Bool
    ) throws -> SpecImportResult {
        let url = try fixtureInputURL(named: name, preferJSON: false)
        let data = try Data(contentsOf: url)
        return try parseSpec(
            bytes: data,
            sourceHint: .har,
            bundleEntryPath: nil,
            options: SpecParseOptions(
                enableSchemaSynthesis: false,
                importHarCredentialsAsPlaceholders: importHarCredentialsAsPlaceholders
            )
        )
    }

    private func fixtureInputURL(named name: String, preferJSON: Bool) throws -> URL {
        let yamlURL = Self.fixturesDirectory.appendingPathComponent("\(name).input.yaml")
        let jsonURL = Self.fixturesDirectory.appendingPathComponent("\(name).input.json")
        let harURL = Self.fixturesDirectory.appendingPathComponent("\(name).input.har")
        let graphqlURL = Self.fixturesDirectory.appendingPathComponent("\(name).input.graphql")

        if preferJSON, FileManager.default.fileExists(atPath: jsonURL.path) {
            return jsonURL
        }
        if FileManager.default.fileExists(atPath: yamlURL.path) {
            return yamlURL
        }
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            return jsonURL
        }
        if FileManager.default.fileExists(atPath: harURL.path) {
            return harURL
        }
        if FileManager.default.fileExists(atPath: graphqlURL.path) {
            return graphqlURL
        }
        throw FixtureError.missingInput(name)
    }

    private func sourceHint(for url: URL) -> SpecSourceHint {
        switch url.pathExtension.lowercased() {
        case "json": .json
        case "har": .har
        case "graphql", "gql": .graphql
        case "yaml", "yml": .yaml
        default: .json
        }
    }

    private func mapFixture(
        _ result: SpecImportResult,
        name: String,
        options: GoldenFixtureOptions = GoldenFixtureOptions(),
        importHarCredentialsAsPlaceholders: Bool = false
    ) -> SpecImportMappedResult {
        var importOptions = SpecImportOptions.default
        importOptions.folderStrategy = options.folderStrategy
        importOptions.importHarCredentialsAsPlaceholders = importHarCredentialsAsPlaceholders

        return SpecImportMapper.map(
            result,
            projectId: projectId(for: name),
            options: importOptions,
            idContext: idContext(for: name)
        )
    }

    private func projectId(for fixture: String) -> UUID {
        SpecImportMapper.deterministicUUID("spec-import-project:\(fixture)")
    }

    private func idContext(for fixture: String) -> SpecImportIDContext {
        SpecImportIDContext(projectId: projectId(for: fixture), namespace: fixture)
    }

    private enum FixtureError: Error {
        case missingInput(String)
    }
}

// MARK: - Golden encoding

private struct SpecImportProjectGolden: Codable, Equatable {
    var project: GoldenProject
    var folders: [GoldenFolder]
    var requests: [GoldenRequest]
    var environments: [GoldenEnvironment]

    init(from mapped: SpecImportMappedResult) {
        project = GoldenProject(from: mapped.project)
        folders = mapped.folders.map(GoldenFolder.init)
        requests = mapped.requests.map(GoldenRequest.init)
        environments = mapped.environments.map(GoldenEnvironment.init)
    }
}

private struct GoldenProject: Codable, Equatable {
    var id: String
    var name: String

    init(from project: Project) {
        id = project.id.uuidString.lowercased()
        name = project.name
    }
}

private struct GoldenFolder: Codable, Equatable {
    var id: String
    var name: String

    init(from folder: RequestFolder) {
        id = folder.id.uuidString.lowercased()
        name = folder.name
    }
}

private struct GoldenRequest: Codable, Equatable {
    var id: String
    var name: String
    var folderId: String?
    var sortOrder: Int
    var specIdentity: SpecOperationIdentity?
    var http: GoldenHttpRequestData?
    var webSocket: GoldenWebSocketRequestData?

    init(from request: Request) {
        id = request.id.uuidString.lowercased()
        name = request.name
        folderId = request.folderId?.uuidString.lowercased()
        sortOrder = request.sortOrder
        specIdentity = request.specIdentity
        http = request.httpData.map(GoldenHttpRequestData.init)
        webSocket = request.webSocketData.map(GoldenWebSocketRequestData.init)
    }
}

private struct GoldenWebSocketRequestData: Codable, Equatable {
    var url: String
    var headers: [GoldenKeyValue]
    var subprotocols: String
    var encoding: DataEncoding
    var messageHistory: [GoldenMessageHistoryEntry]

    init(from data: WebSocketRequestData) {
        url = data.url
        headers = data.headers.filter { !$0.isEmpty }.map(GoldenKeyValue.init)
        subprotocols = data.subprotocols
        encoding = data.encoding
        messageHistory = data.messageHistory.map(GoldenMessageHistoryEntry.init)
    }
}

private struct GoldenMessageHistoryEntry: Codable, Equatable {
    var text: String
    var encoding: DataEncoding

    init(from entry: MessageHistoryEntry) {
        text = entry.text
        encoding = entry.encoding
    }
}

private struct GoldenHttpRequestData: Codable, Equatable {
    var method: String
    var url: String
    var params: [GoldenKeyValue]
    var headers: [GoldenKeyValue]
    var bodyType: HttpBodyType
    var bodyContent: String
    var bodyFormData: [GoldenKeyValue]
    var bodyFormDataEntries: [GoldenFormDataEntry]
    var rawContentType: HttpRawContentType?
    var binaryFileName: String
    var authType: HttpAuthType
    var authToken: String
    var authUsername: String
    var authPassword: String
    var authApiKeyName: String
    var authApiKeyValue: String
    var authApiKeyLocation: String
    var authOAuth2GrantType: String
    var authOAuth2AuthURL: String
    var authOAuth2TokenURL: String
    var authOAuth2Scopes: String

    init(from data: HttpRequestData) {
        method = data.method.rawLabel
        url = data.url
        params = data.params.filter { !$0.isEmpty }.map(GoldenKeyValue.init)
        headers = data.headers.filter { !$0.isEmpty }.map(GoldenKeyValue.init)
        bodyType = data.bodyType
        bodyContent = data.bodyContent
        bodyFormData = data.bodyFormData.filter { !$0.isEmpty }.map(GoldenKeyValue.init)
        bodyFormDataEntries = data.bodyFormDataEntries.filter { !$0.isEmpty }.map(GoldenFormDataEntry.init)
        rawContentType = data.rawContentType
        binaryFileName = data.binaryFileName
        authType = data.authType
        authToken = data.authToken
        authUsername = data.authUsername
        authPassword = data.authPassword
        authApiKeyName = data.authApiKeyName
        authApiKeyValue = data.authApiKeyValue
        authApiKeyLocation = data.authApiKeyLocation
        authOAuth2GrantType = data.authOAuth2GrantType
        authOAuth2AuthURL = data.authOAuth2AuthURL
        authOAuth2TokenURL = data.authOAuth2TokenURL
        authOAuth2Scopes = data.authOAuth2Scopes
    }
}

private struct GoldenKeyValue: Codable, Equatable {
    var key: String
    var value: String
    var enabled: Bool

    init(from entry: KeyValueEntry) {
        key = entry.key
        value = entry.value
        enabled = entry.enabled
    }
}

private struct GoldenFormDataEntry: Codable, Equatable {
    var key: String
    var value: String
    var enabled: Bool
    var fieldType: FormDataFieldType
    var fileName: String
    var mimeType: String

    init(from entry: FormDataEntry) {
        key = entry.key
        value = entry.value
        enabled = entry.enabled
        fieldType = entry.fieldType
        fileName = entry.fileName
        mimeType = entry.mimeType
    }
}

private struct GoldenEnvironment: Codable, Equatable {
    var id: String
    var name: String
    var isActive: Bool
    var variables: [GoldenEnvironmentVariable]

    init(from environment: ApiEnvironment) {
        id = environment.id.uuidString.lowercased()
        name = environment.name
        isActive = environment.isActive
        variables = environment.variables.map(GoldenEnvironmentVariable.init)
    }
}

private struct GoldenEnvironmentVariable: Codable, Equatable {
    var key: String
    var value: String
    var enabled: Bool

    init(from variable: EnvironmentVariable) {
        key = variable.key
        value = variable.value
        enabled = variable.enabled
    }
}