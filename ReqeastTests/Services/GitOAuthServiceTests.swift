//
//  GitOAuthServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("GitOAuthService", .serialized)
@MainActor
struct GitOAuthServiceTests {

    private let testClientID = "test-client-id"
    private let account = GitOAuthAccount(provider: .github, owner: "acme", host: nil)

    @Test func requestDeviceCodeParsesGitHubResponse() async throws {
        let service = makeService { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "https://github.com/login/device/code")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
            #expect(body?.contains("client_id=\(testClientID)") == true)
            #expect(body?.contains("scope=repo") == true)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            let payload = """
            {
              "device_code": "device-123",
              "user_code": "ABCD-1234",
              "verification_uri": "https://github.com/login/device",
              "verification_uri_complete": "https://github.com/login/device?code=ABCD-1234",
              "expires_in": 900,
              "interval": 5
            }
            """
            return (Data(payload.utf8), response)
        }

        let session = try await service.requestDeviceCode(account: account)

        #expect(session.deviceCode == "device-123")
        #expect(session.userCode == "ABCD-1234")
        #expect(session.verificationURI.absoluteString == "https://github.com/login/device")
        #expect(session.verificationURIComplete?.absoluteString == "https://github.com/login/device?code=ABCD-1234")
        #expect(session.expiresIn == 900)
        #expect(session.interval == 5)
        #expect(session.host == nil)
    }

    @Test func pollForAccessTokenReturnsToken() async throws {
        var pollCount = 0
        let service = makeService { request in
            #expect(request.url?.absoluteString == "https://github.com/login/oauth/access_token")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
            #expect(body?.contains("grant_type=urn:ietf:params:oauth:grant-type:device_code") == true)
            #expect(body?.contains("device_code=device-123") == true)

            pollCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!

            let payload: String
            if pollCount == 1 {
                payload = #"{"error":"authorization_pending"}"#
            } else {
                payload = #"{"access_token":"gho_test_token","token_type":"bearer","scope":"repo"}"#
            }
            return (Data(payload.utf8), response)
        }

        let session = GitDeviceCodeSession(
            deviceCode: "device-123",
            userCode: "ABCD-1234",
            verificationURI: URL(string: "https://github.com/login/device")!,
            verificationURIComplete: nil,
            expiresIn: 30,
            interval: 0,
            host: nil
        )

        let token = try await service.pollForAccessToken(session: session)
        #expect(token == "gho_test_token")
        #expect(pollCount == 2)
    }

    @Test func pollForAccessTokenHandlesExpiredToken() async throws {
        let service = makeService { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data(#"{"error":"expired_token"}"#.utf8), response)
        }

        let session = GitDeviceCodeSession(
            deviceCode: "device-123",
            userCode: "ABCD-1234",
            verificationURI: URL(string: "https://github.com/login/device")!,
            verificationURIComplete: nil,
            expiresIn: 30,
            interval: 0,
            host: nil
        )

        await #expect(throws: GitOAuthError.expiredToken) {
            try await service.pollForAccessToken(session: session)
        }
    }

    @Test func saveManualTokenStoresNonSyncedKeychainEntry() throws {
        let keychain = GitTokenKeychainService.shared
        let key = account.tokenKey
        defer {
            try? keychain.deleteToken(forKey: key)
            GitOAuthAccountRegistry.remove(account)
        }

        let service = GitOAuthService(
            httpClient: MockGitOAuthHTTPClient(handler: { _ in throw URLError(.badURL) }),
            keychain: keychain,
            clientIDProvider: { testClientID }
        )

        try service.saveManualToken("ghp_manual_token", account: account)

        let loaded = try keychain.loadToken(forKey: key)
        #expect(loaded == "ghp_manual_token")
        #expect(GitOAuthAccountRegistry.accounts().contains(account))
        #expect(service.hasStoredToken(for: account))
    }

    @Test func enterpriseHostRequiresTrustedAllowlist() async throws {
        let originalHosts = SafeFetchTrustedHosts.hosts
        SafeFetchTrustedHosts.hosts = []
        defer { SafeFetchTrustedHosts.hosts = originalHosts }

        let enterpriseAccount = GitOAuthAccount(
            provider: .github,
            owner: "acme",
            host: "github.example.com"
        )
        let service = makeService { _ in throw URLError(.badURL) }

        await #expect(throws: GitOAuthError.hostNotAllowed("github.example.com")) {
            try await service.requestDeviceCode(account: enterpriseAccount)
        }
    }

    @Test func enterpriseHostUsesCustomOAuthEndpoints() async throws {
        let originalHosts = SafeFetchTrustedHosts.hosts
        SafeFetchTrustedHosts.hosts = ["github.example.com"]
        defer { SafeFetchTrustedHosts.hosts = originalHosts }

        let enterpriseAccount = GitOAuthAccount(
            provider: .github,
            owner: "acme",
            host: "github.example.com"
        )

        let service = makeService { request in
            #expect(request.url?.absoluteString == "https://github.example.com/login/device/code")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            let payload = """
            {
              "device_code": "ent-device",
              "user_code": "ENTR-1234",
              "verification_uri": "https://github.example.com/login/device",
              "expires_in": 900,
              "interval": 5
            }
            """
            return (Data(payload.utf8), response)
        }

        let session = try await service.requestDeviceCode(account: enterpriseAccount)
        #expect(session.deviceCode == "ent-device")
        #expect(session.host == "github.example.com")
    }

    @Test func completeDeviceFlowSavesTokenForGitSpecFetch() async throws {
        let keychain = GitTokenKeychainService.shared
        let key = account.tokenKey
        defer {
            try? keychain.deleteToken(forKey: key)
            GitOAuthAccountRegistry.remove(account)
        }

        let service = makeService { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!

            if request.url?.path == "/login/device/code" {
                let payload = """
                {
                  "device_code": "device-xyz",
                  "user_code": "WXYZ-5678",
                  "verification_uri": "https://github.com/login/device",
                  "expires_in": 900,
                  "interval": 0
                }
                """
                return (Data(payload.utf8), response)
            }

            let payload = #"{"access_token":"gho_saved_token","token_type":"bearer","scope":"repo"}"#
            return (Data(payload.utf8), response)
        }

        let session = try await service.requestDeviceCode(account: account)
        try await service.completeDeviceFlow(account: account, session: session)

        let loaded = try keychain.loadToken(forKey: key)
        #expect(loaded == "gho_saved_token")
    }

    // MARK: - Helpers

    private func makeService(
        handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    ) -> GitOAuthService {
        GitOAuthService(
            httpClient: MockGitOAuthHTTPClient(handler: handler),
            keychain: GitTokenKeychainService.shared,
            clientIDProvider: { testClientID }
        )
    }
}

// MARK: - Test Doubles

private struct MockGitOAuthHTTPClient: GitOAuthHTTPClient {
    let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try handler(request)
        return (data, response)
    }
}