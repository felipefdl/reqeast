//
//  SafeFetchTrustedHostsTests.swift
//  ReqeastTests
//

import Testing
@testable import Reqeast

@Suite("SafeFetchTrustedHosts")
struct SafeFetchTrustedHostsTests {

    @Test func builtInGitHostsDoNotRequireUserTrust() {
        #expect(SafeFetchTrustedHosts.isBuiltInGitHost("github.com"))
        #expect(SafeFetchTrustedHosts.isBuiltInGitHost("api.github.com"))
        #expect(SafeFetchTrustedHosts.isBuiltInGitHost("raw.githubusercontent.com"))
        #expect(SafeFetchTrustedHosts.isBuiltInGitHost("ghe.github.com"))
        #expect(SafeFetchTrustedHosts.isBuiltInGitHost("gitlab.com"))
        #expect(SafeFetchTrustedHosts.isBuiltInGitHost("group.gitlab.com"))
        #expect(!SafeFetchTrustedHosts.isBuiltInGitHost("github.example.com"))
    }

    @Test func addAndRemoveTrustedHost() {
        let originalHosts = SafeFetchTrustedHosts.hosts
        defer { SafeFetchTrustedHosts.hosts = originalHosts }

        SafeFetchTrustedHosts.hosts = []
        #expect(SafeFetchTrustedHosts.addHost("HTTPS://GitHub.Example.COM:443/") == "github.example.com")
        #expect(SafeFetchTrustedHosts.hosts == ["github.example.com"])
        #expect(SafeFetchTrustedHosts.isUserTrusted("github.example.com"))

        SafeFetchTrustedHosts.removeHost("github.example.com")
        #expect(SafeFetchTrustedHosts.hosts.isEmpty)
    }

    @Test func rejectsInvalidTrustedHost() {
        let originalHosts = SafeFetchTrustedHosts.hosts
        defer { SafeFetchTrustedHosts.hosts = originalHosts }

        SafeFetchTrustedHosts.hosts = []
        #expect(SafeFetchTrustedHosts.addHost("127.0.0.1") == nil)
        #expect(SafeFetchTrustedHosts.addHost("") == nil)
        #expect(SafeFetchTrustedHosts.hosts.isEmpty)
    }
}