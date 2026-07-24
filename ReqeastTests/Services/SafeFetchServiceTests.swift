//
//  SafeFetchServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

// MARK: - Test Doubles

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

@Suite("SafeFetchService", .serialized)
@MainActor
struct SafeFetchServiceTests {
    private let publicIP = "93.184.216.34"
    private let publicResolver = MockHostResolver(mapping: ["example.com": ["93.184.216.34"]])

    private func makeService(
        resolver: MockHostResolver? = nil,
        trustedHostPolicy: (any TrustedHostPolicy)? = nil,
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> SafeFetchService {
        MockURLProtocol.handler = handler
        return SafeFetchService(
            resolver: resolver ?? publicResolver,
            protocolClasses: [MockURLProtocol.self],
            trustedHostPolicy: trustedHostPolicy ?? DefaultTrustedHostPolicy()
        )
    }

    // MARK: - Blocked IPs (AC11)

    @Test func blocksLiteralLoopbackIPv4() async {
        let service = makeService { request in mockOKResponse(for: request) }
        let url = URL(string: "https://127.0.0.1/spec.yaml")!

        await #expect(throws: SafeFetchError.blockedIPAddress("127.0.0.1")) {
            try await service.fetch(url: url)
        }
    }

    @Test func blocksLiteralPrivateIPv4_10x() async {
        let service = makeService { request in mockOKResponse(for: request) }
        let url = URL(string: "https://10.0.0.1/spec.yaml")!

        await #expect(throws: SafeFetchError.blockedIPAddress("10.0.0.1")) {
            try await service.fetch(url: url)
        }
    }

    @Test func blocksLiteralPrivateIPv4_192_168x() async {
        let service = makeService { request in mockOKResponse(for: request) }
        let url = URL(string: "https://192.168.1.50/spec.yaml")!

        await #expect(throws: SafeFetchError.blockedIPAddress("192.168.1.50")) {
            try await service.fetch(url: url)
        }
    }

    @Test func blocksLiteralLinkLocalIPv4() async {
        let service = makeService { request in mockOKResponse(for: request) }
        let url = URL(string: "https://169.254.1.1/spec.yaml")!

        await #expect(throws: SafeFetchError.blockedIPAddress("169.254.1.1")) {
            try await service.fetch(url: url)
        }
    }

    @Test func blocksMetadataIPv4() async {
        let service = makeService { request in mockOKResponse(for: request) }
        let url = URL(string: "https://169.254.169.254/latest/meta-data")!

        await #expect(throws: SafeFetchError.blockedIPAddress("169.254.169.254")) {
            try await service.fetch(url: url)
        }
    }

    @Test func blocksLiteralLoopbackIPv6() async {
        let service = makeService { request in mockOKResponse(for: request) }
        let url = URL(string: "https://[::1]/spec.yaml")!

        await #expect(throws: SafeFetchError.blockedIPAddress("::1")) {
            try await service.fetch(url: url)
        }
    }

    @Test func blocksLiteralUniqueLocalIPv6() async {
        let service = makeService { request in mockOKResponse(for: request) }
        let url = URL(string: "https://[fc00::1]/spec.yaml")!

        await #expect(throws: SafeFetchError.blockedIPAddress("fc00::1")) {
            try await service.fetch(url: url)
        }
    }

    @Test func blocksLiteralLinkLocalIPv6() async {
        let service = makeService { request in mockOKResponse(for: request) }
        let url = URL(string: "https://[fe80::1]/spec.yaml")!

        await #expect(throws: SafeFetchError.blockedIPAddress("fe80::1")) {
            try await service.fetch(url: url)
        }
    }

    @Test func blocksIPv4MappedLoopbackIPv6() async {
        let service = makeService { request in mockOKResponse(for: request) }
        let url = URL(string: "https://[::ffff:127.0.0.1]/spec.yaml")!

        await #expect(throws: SafeFetchError.blockedIPAddress("::ffff:127.0.0.1")) {
            try await service.fetch(url: url)
        }
    }

    @Test func blocksIPv4MappedPrivateIPv6() async {
        let service = makeService { request in mockOKResponse(for: request) }
        let url = URL(string: "https://[::ffff:10.0.0.1]/spec.yaml")!

        await #expect(throws: SafeFetchError.blockedIPAddress("::ffff:10.0.0.1")) {
            try await service.fetch(url: url)
        }
    }

    @Test func blocksResolvedPrivateIPv4() async {
        let resolver = MockHostResolver(mapping: ["internal.example": ["10.20.30.40"]])
        let service = makeService(resolver: resolver) { request in mockOKResponse(for: request) }
        let url = URL(string: "https://internal.example/spec.yaml")!

        await #expect(throws: SafeFetchError.blockedIPAddress("10.20.30.40")) {
            try await service.fetch(url: url)
        }
    }

    // MARK: - Scheme Policy

    @Test func rejectsHTTPUnlessHostIsTrusted() async {
        let service = makeService { request in mockOKResponse(for: request) }
        let url = URL(string: "http://example.com/spec.yaml")!

        await #expect(throws: SafeFetchError.httpNotAllowed) {
            try await service.fetch(url: url)
        }
    }

    @Test func acceptsHTTPOnTrustedHost() async throws {
        let policy = FixedTrustedHostPolicy(httpHosts: ["example.com"])
        let service = makeService(trustedHostPolicy: policy) { request in mockOKResponse(for: request) }
        let url = URL(string: "http://example.com/spec.yaml")!

        let data = try await service.fetch(url: url)
        #expect(String(data: data, encoding: .utf8) == "ok")
    }

    @Test func allowsPrivateIPForTrustedHost() async throws {
        let policy = FixedTrustedHostPolicy(
            allowedGitHosts: ["github.example.com"],
            privateIPHosts: ["github.example.com"]
        )
        let resolver = MockHostResolver(mapping: ["github.example.com": ["10.20.30.40"]])
        let service = makeService(resolver: resolver, trustedHostPolicy: policy) { request in
            #expect(request.url?.host == "10.20.30.40")
            #expect(request.value(forHTTPHeaderField: "Host") == "github.example.com")
            return mockOKResponse(for: request, body: Data("enterprise".utf8))
        }
        let url = URL(string: "https://github.example.com/api/v3/repos/acme/api/contents/openapi.yaml?ref=main")!

        let data = try await service.fetch(url: url, requireTrustedHost: true)
        #expect(String(data: data, encoding: .utf8) == "enterprise")
    }

    @Test func rejectsUntrustedGitEnterpriseHost() async {
        let resolver = MockHostResolver(mapping: ["github.example.com": ["93.184.216.34"]])
        let service = makeService(
            resolver: resolver,
            trustedHostPolicy: FixedTrustedHostPolicy()
        ) { request in mockOKResponse(for: request) }
        let url = URL(string: "https://github.example.com/api/v3/repos/acme/api/contents/openapi.yaml?ref=main")!

        await #expect(throws: SafeFetchError.hostNotTrusted("github.example.com")) {
            try await service.fetch(url: url, requireTrustedHost: true)
        }
    }

    // MARK: - Successful Fetch

    @Test func acceptsHTTPSWithPublicResolvedIP() async throws {
        let body = Data("openapi: 3.0.0".utf8)
        let service = makeService { request in
            #expect(request.url?.host == "93.184.216.34")
            #expect(request.value(forHTTPHeaderField: "Host") == "example.com")
            #expect(request.httpShouldHandleCookies == false)
            return mockOKResponse(for: request, body: body)
        }
        let url = URL(string: "https://example.com/openapi.yaml")!

        let data = try await service.fetch(url: url)
        #expect(data == body)
    }

    @Test func acceptsHTTPSWithLiteralPublicIP() async throws {
        let service = makeService { request in mockOKResponse(for: request) }
        let url = URL(string: "https://8.8.8.8/spec.yaml")!

        let data = try await service.fetch(url: url)
        #expect(String(data: data, encoding: .utf8) == "ok")
    }

    // MARK: - Redirect Cap

    @Test func enforcesRedirectHopCap() async {
        let service = makeService { request in
            let path = request.url?.path ?? "/"
            let nextHop = (Int(path.dropFirst()) ?? 0) + 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": "/\(nextHop)"]
            )!
            return (response, Data())
        }
        let url = URL(string: "https://example.com/0")!

        await #expect(throws: SafeFetchError.tooManyRedirects) {
            try await service.fetch(url: url)
        }
    }

    @Test func rejectsRedirectToBlockedHost() async {
        let service = makeService { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": "https://127.0.0.1/internal"]
            )!
            return (response, Data())
        }
        let url = URL(string: "https://example.com/start")!

        await #expect(throws: SafeFetchError.blockedIPAddress("127.0.0.1")) {
            try await service.fetch(url: url)
        }
    }

    @Test func rejectsRedirectToHostnameResolvingToPrivateIP() async {
        let resolver = MockHostResolver(mapping: [
            "example.com": ["93.184.216.34"],
            "internal.evil": ["10.0.0.55"],
        ])
        let service = makeService(resolver: resolver) { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": "https://internal.evil/spec.yaml"]
            )!
            return (response, Data())
        }
        let url = URL(string: "https://example.com/start")!

        await #expect(throws: SafeFetchError.blockedIPAddress("10.0.0.55")) {
            try await service.fetch(url: url)
        }
    }

    // MARK: - Body Size Cap

    @Test func enforcesBodySizeCapFromContentLength() async {
        let service = makeService { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(SafeFetchLimits.maxBodyBytes + 1)"]
            )!
            return (response, Data())
        }
        let url = URL(string: "https://example.com/large.yaml")!

        await #expect(throws: SafeFetchError.responseTooLarge) {
            try await service.fetch(url: url)
        }
    }

    @Test func enforcesBodySizeCapFromPayload() async {
        let oversized = Data(repeating: 0xAB, count: SafeFetchLimits.maxBodyBytes + 1)
        let service = makeService { request in
            mockOKResponse(for: request, body: oversized)
        }
        let url = URL(string: "https://example.com/large.yaml")!

        await #expect(throws: SafeFetchError.responseTooLarge) {
            try await service.fetch(url: url)
        }
    }

    @Test func enforcesBodySizeCapMidStream() async {
        let service = makeService { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            let oversized = Data(repeating: 0xCD, count: SafeFetchLimits.maxBodyBytes + 1)
            return (response, oversized)
        }
        let url = URL(string: "https://example.com/streamed-large.yaml")!

        await #expect(throws: SafeFetchError.responseTooLarge) {
            try await service.fetch(url: url)
        }
    }
}
