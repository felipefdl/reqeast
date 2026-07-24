//
//  GitSourceRefTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("GitSourceRef")
struct GitSourceRefTests {

    @Test func gitSourceRefRoundTripPreservesNewFields() throws {
        let gitRef = GitSourceRef(
            hostBaseURL: "https://github.example.com/api/v3",
            provider: .github,
            owner: "acme",
            repo: "api",
            ref: "main",
            path: "openapi.yaml",
            tokenKey: "github:acme"
        )

        let decoded = try roundTrip(gitRef)
        #expect(decoded == gitRef)
    }

    @Test func specLinkWithGitRefRoundTrip() throws {
        let link = SpecLink(
            format: .openapi,
            source: .gitProvider,
            contentFingerprint: "abc",
            importedAt: Date(timeIntervalSinceReferenceDate: 1000),
            sourceURL: "https://github.com/acme/api/blob/main/openapi.yaml",
            gitRef: GitSourceRef(
                provider: .github,
                owner: "acme",
                repo: "api",
                ref: "main",
                path: "openapi.yaml",
                tokenKey: "github:acme"
            ),
            isDetached: false
        )

        let decoded = try roundTrip(link)
        #expect(decoded.source == .gitProvider)
        #expect(decoded.gitRef?.owner == "acme")
        #expect(decoded.gitRef?.path == "openapi.yaml")
    }

    @Test func gitTokenKeychainIsNonSynced() throws {
        let key = GitTokenKeychainService.tokenKey(provider: .github, owner: "acme")
        try GitTokenKeychainService.shared.saveToken("secret-token", forKey: key)
        defer { try? GitTokenKeychainService.shared.deleteToken(forKey: key) }

        let loaded = try GitTokenKeychainService.shared.loadToken(forKey: key)
        #expect(loaded == "secret-token")
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: encoded)
        #expect(decoded == value)
        return decoded
    }
}