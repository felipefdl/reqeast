//
//  GitSpecSourceServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("GitSpecSourceService", .serialized)
@MainActor
struct GitSpecSourceServiceTests {

    // MARK: - URL Parsing

    @Test func parseGitHubRawURL() {
        let url = "https://raw.githubusercontent.com/acme/api/main/openapi.yaml"
        let parsed = GitImportURLParser.parse(url)
        guard case .rawHTTPS(let resolvedURL, let gitRef) = parsed else {
            Issue.record("Expected rawHTTPS source")
            return
        }

        #expect(resolvedURL.absoluteString == url)
        #expect(gitRef?.provider == .github)
        #expect(gitRef?.owner == "acme")
        #expect(gitRef?.repo == "api")
        #expect(gitRef?.ref == "main")
        #expect(gitRef?.path == "openapi.yaml")
        #expect(gitRef?.tokenKey == "github:acme")
    }

    @Test func parseGitHubBlobURLAsProvider() {
        let url = "https://github.com/acme/api/blob/main/specs/openapi.yaml"
        let parsed = GitImportURLParser.parse(url)
        guard case .provider(let gitRef, let canonicalURL) = parsed else {
            Issue.record("Expected provider source")
            return
        }

        #expect(canonicalURL == url)
        #expect(gitRef.provider == .github)
        #expect(gitRef.owner == "acme")
        #expect(gitRef.repo == "api")
        #expect(gitRef.ref == "main")
        #expect(gitRef.path == "specs/openapi.yaml")
        #expect(gitRef.hostBaseURL == "https://api.github.com")
    }

    @Test func parseGitLabRawURL() {
        let url = "https://gitlab.com/acme/api/-/raw/main/docs/openapi.yaml"
        let parsed = GitImportURLParser.parse(url)
        guard case .rawHTTPS(_, let gitRef) = parsed else {
            Issue.record("Expected rawHTTPS source")
            return
        }

        #expect(gitRef?.provider == .gitlab)
        #expect(gitRef?.owner == "acme")
        #expect(gitRef?.repo == "api")
        #expect(gitRef?.ref == "main")
        #expect(gitRef?.path == "docs/openapi.yaml")
    }

    @Test func parseNonGitURLReturnsNil() {
        #expect(GitImportURLParser.parse("https://example.com/openapi.yaml") == nil)
        #expect(GitImportURLParser.parse("http://raw.githubusercontent.com/a/b/c/d") == nil)
        #expect(
            GitImportURLParser.parse(
                "https://docs.connect-api.1global.com/spec/version-2026-02-05/spec.yml"
            ) == nil
        )
        #expect(GitImportURLParser.parse("https://docs.tago.io/specs/tagoio-api.yaml") == nil)
    }

    @Test func parseTagoIODocsRawGitHubURL() {
        let url = "https://raw.githubusercontent.com/tago-io/docs/refs/heads/main/specs/tagoio-api.yaml"
        let parsed = GitImportURLParser.parse(url)
        guard case .rawHTTPS(let resolvedURL, let gitRef) = parsed else {
            Issue.record("Expected rawHTTPS source for TagoIO docs spec URL")
            return
        }

        #expect(resolvedURL.absoluteString == url)
        #expect(gitRef?.provider == .github)
        #expect(gitRef?.owner == "tago-io")
        #expect(gitRef?.repo == "docs")
        #expect(gitRef?.ref == "main")
        #expect(gitRef?.path == "specs/tagoio-api.yaml")
    }

    @Test func parseGitHubEnterpriseBlobURLWhenHostIsTrusted() {
        let originalHosts = SafeFetchTrustedHosts.hosts
        SafeFetchTrustedHosts.hosts = ["github.example.com"]
        defer { SafeFetchTrustedHosts.hosts = originalHosts }

        let url = "https://github.example.com/acme/api/blob/main/openapi.yaml"
        let parsed = GitImportURLParser.parse(url)
        guard case .provider(let gitRef, let canonicalURL) = parsed else {
            Issue.record("Expected provider source for enterprise blob URL")
            return
        }

        #expect(canonicalURL == url)
        #expect(gitRef.provider == .github)
        #expect(gitRef.hostBaseURL == "https://github.example.com/api/v3")
        #expect(gitRef.owner == "acme")
        #expect(gitRef.repo == "api")
        #expect(gitRef.ref == "main")
        #expect(gitRef.path == "openapi.yaml")
    }

    @Test func parseGitHubEnterpriseBlobURLWithoutTrustReturnsNil() {
        let originalHosts = SafeFetchTrustedHosts.hosts
        SafeFetchTrustedHosts.hosts = []
        defer { SafeFetchTrustedHosts.hosts = originalHosts }

        let url = "https://github.example.com/acme/api/blob/main/openapi.yaml"
        #expect(GitImportURLParser.parse(url) == nil)
    }

    // MARK: - Provider Fetch

    @Test @MainActor func fetchGitHubProviderUsesRawAcceptHeader() async throws {
        let gitRef = GitSourceRef(
            hostBaseURL: "https://api.github.com",
            provider: .github,
            owner: "acme",
            repo: "api",
            ref: "main",
            path: "openapi.yaml",
            tokenKey: nil
        )

        var capturedRequest: URLRequest?
        let service = makeMockFetchService { request in
            capturedRequest = request
            return mockOKResponse(for: request, body: Data("openapi: 3.1.0".utf8))
        }

        _ = try await fetchProviderSpec(using: service, gitRef: gitRef)

        #expect(capturedRequest?.value(forHTTPHeaderField: "Accept") == "application/vnd.github.raw")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Host") == "api.github.com")
        #expect(capturedRequest?.url?.path == "/repos/acme/api/contents/openapi.yaml")
        #expect(capturedRequest?.url?.query == "ref=main")
    }

    @Test @MainActor func fetchGitHubProviderAttachesPATFromKeychain() async throws {
        let tokenKey = GitTokenKeychainService.tokenKey(provider: .github, owner: "acme")
        try GitTokenKeychainService.shared.saveToken("ghp_test_token", forKey: tokenKey)
        defer { try? GitTokenKeychainService.shared.deleteToken(forKey: tokenKey) }

        let gitRef = GitSourceRef(
            hostBaseURL: "https://api.github.com",
            provider: .github,
            owner: "acme",
            repo: "api",
            ref: "main",
            path: "openapi.yaml",
            tokenKey: tokenKey
        )

        var capturedRequest: URLRequest?
        let service = makeMockFetchService { request in
            capturedRequest = request
            return mockOKResponse(for: request)
        }

        _ = try await fetchProviderSpec(using: service, gitRef: gitRef)
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_test_token")
    }

    @Test @MainActor func fetchGitHubEnterpriseProviderUsesHostBaseURL() async throws {
        let gitRef = GitSourceRef(
            hostBaseURL: "https://github.example.com/api/v3",
            provider: .github,
            owner: "acme",
            repo: "api",
            ref: "main",
            path: "openapi.yaml",
            tokenKey: nil
        )

        var capturedRequest: URLRequest?
        let service = makeMockFetchService(
            resolver: MockHostResolver(mapping: ["github.example.com": ["10.0.0.5"]]),
            trustedHostPolicy: FixedTrustedHostPolicy(
                allowedGitHosts: ["github.example.com"],
                privateIPHosts: ["github.example.com"]
            ),
            handler: { request in
                capturedRequest = request
                return mockOKResponse(for: request, body: Data("openapi: 3.1.0".utf8))
            }
        )

        _ = try await fetchProviderSpec(using: service, gitRef: gitRef)

        #expect(capturedRequest?.value(forHTTPHeaderField: "Host") == "github.example.com")
        #expect(capturedRequest?.url?.path == "/api/v3/repos/acme/api/contents/openapi.yaml")
        #expect(capturedRequest?.url?.query == "ref=main")
    }

    @Test @MainActor func fetchGitHubProviderMaps401ToTokenRequired() async throws {
        let gitRef = GitSourceRef(
            hostBaseURL: "https://api.github.com",
            provider: .github,
            owner: "acme",
            repo: "private-api",
            ref: "main",
            path: "openapi.yaml",
            tokenKey: nil
        )

        let service = makeMockFetchService { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, Data())
        }

        await #expect(throws: GitSpecSourceError.tokenRequired) {
            try await fetchProviderSpec(using: service, gitRef: gitRef)
        }
    }

    // MARK: - Linked Fetch

    @Test @MainActor func fetchLinkedGitHTTPSUsesSourceURL() async throws {
        let specLink = SpecLink(
            format: .openapi,
            source: .gitHTTPS,
            contentFingerprint: "fp",
            importedAt: Date(),
            sourceURL: "https://raw.githubusercontent.com/acme/api/main/openapi.yaml"
        )

        var capturedHostHeader: String?
        let service = makeMockFetchService { request in
            capturedHostHeader = request.value(forHTTPHeaderField: "Host")
            return mockOKResponse(for: request, body: Data("openapi: 3.1.0".utf8))
        }

        _ = try await fetchLinkedSpec(using: service, specLink: specLink, projectId: UUID())
        #expect(capturedHostHeader == "raw.githubusercontent.com")
    }

    // MARK: - Helpers

    private func makeMockFetchService(
        resolver: MockHostResolver? = nil,
        trustedHostPolicy: (any TrustedHostPolicy)? = nil,
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> SafeFetchService {
        MockURLProtocol.handler = handler
        return SafeFetchService(
            resolver: resolver ?? MockHostResolver(mapping: [
                "api.github.com": ["93.184.216.34"],
                "raw.githubusercontent.com": ["93.184.216.34"],
            ]),
            protocolClasses: [MockURLProtocol.self],
            trustedHostPolicy: trustedHostPolicy ?? DefaultTrustedHostPolicy()
        )
    }

    @MainActor
    private func fetchProviderSpec(using service: SafeFetchService, gitRef: GitSourceRef) async throws -> Data {
        let original = SafeFetchService.shared
        SafeFetchService.shared = service
        defer { SafeFetchService.shared = original }
        return try await GitSpecSourceService.fetchImportSource(.provider(gitRef: gitRef, canonicalURL: "test"))
    }

    @MainActor
    private func fetchLinkedSpec(
        using service: SafeFetchService,
        specLink: SpecLink,
        projectId: UUID
    ) async throws -> Data {
        let original = SafeFetchService.shared
        SafeFetchService.shared = service
        defer { SafeFetchService.shared = original }
        return try await GitSpecSourceService.fetchLinkedSpec(specLink: specLink, projectId: projectId)
    }
}

// MARK: - Test Doubles (shared with SafeFetchServiceTests pattern)

private struct MockHostResolver: HostResolving {
    let mapping: [String: [String]]

    func resolve(hostname: String) throws -> [String] {
        guard let addresses = mapping[hostname] else {
            throw SafeFetchError.dnsResolutionFailed(hostname)
        }
        return addresses
    }
}

nonisolated private func mockOKResponse(for request: URLRequest, body: Data = Data("ok".utf8)) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: nil
    )!
    return (response, body)
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canInit(with task: URLSessionTask) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}