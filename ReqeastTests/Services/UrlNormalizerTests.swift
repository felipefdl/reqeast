//
//  UrlNormalizerTests.swift
//  ReqeastTests
//

import Testing
@testable import Reqeast

@Suite("UrlNormalizer")
struct UrlNormalizerTests {
    @Test func passesThroughWithScheme() {
        #expect(UrlNormalizer.normalize("http://example.com") == "http://example.com")
        #expect(UrlNormalizer.normalize("https://example.com") == "https://example.com")
        #expect(UrlNormalizer.normalize("ftp://files.example.com") == "ftp://files.example.com")
    }

    @Test func emptyInput() {
        #expect(UrlNormalizer.normalize("") == "")
        #expect(UrlNormalizer.normalize("   ") == "")
    }

    @Test func localhost() {
        #expect(UrlNormalizer.normalize("localhost") == "http://localhost")
        #expect(UrlNormalizer.normalize("localhost:3000") == "http://localhost:3000")
        #expect(UrlNormalizer.normalize("localhost:3000/api") == "http://localhost:3000/api")
    }

    @Test func localhostSubdomain() {
        #expect(UrlNormalizer.normalize("api.localhost") == "http://api.localhost")
        #expect(UrlNormalizer.normalize("api.localhost:8080") == "http://api.localhost:8080")
    }

    @Test func dotLocal() {
        #expect(UrlNormalizer.normalize("myserver.local") == "http://myserver.local")
        #expect(UrlNormalizer.normalize("myserver.local:9090") == "http://myserver.local:9090")
    }

    @Test func loopbackIPs() {
        #expect(UrlNormalizer.normalize("127.0.0.1") == "http://127.0.0.1")
        #expect(UrlNormalizer.normalize("127.0.0.1:8080") == "http://127.0.0.1:8080")
        #expect(UrlNormalizer.normalize("0.0.0.0") == "http://0.0.0.0")
        #expect(UrlNormalizer.normalize("0.0.0.0:3000") == "http://0.0.0.0:3000")
        #expect(UrlNormalizer.normalize("[::1]") == "http://[::1]")
        #expect(UrlNormalizer.normalize("[::1]:8080") == "http://[::1]:8080")
    }

    @Test func privateIPs() {
        #expect(UrlNormalizer.normalize("10.0.0.1") == "http://10.0.0.1")
        #expect(UrlNormalizer.normalize("10.0.0.1:3000") == "http://10.0.0.1:3000")
        #expect(UrlNormalizer.normalize("192.168.1.1") == "http://192.168.1.1")
        #expect(UrlNormalizer.normalize("192.168.1.1:8080") == "http://192.168.1.1:8080")
        #expect(UrlNormalizer.normalize("172.16.0.1") == "http://172.16.0.1")
        #expect(UrlNormalizer.normalize("172.31.255.255") == "http://172.31.255.255")
    }

    @Test func port443() {
        #expect(UrlNormalizer.normalize("api.example.com:443") == "https://api.example.com:443")
    }

    @Test func otherPorts() {
        #expect(UrlNormalizer.normalize("api.example.com:8080") == "http://api.example.com:8080")
        #expect(UrlNormalizer.normalize("api.example.com:3000") == "http://api.example.com:3000")
    }

    @Test func externalDomainNoPort() {
        #expect(UrlNormalizer.normalize("api.example.com") == "https://api.example.com")
        #expect(UrlNormalizer.normalize("example.com/api/v1") == "https://example.com/api/v1")
    }

    @Test func localhostPort443Priority() {
        #expect(UrlNormalizer.normalize("localhost:443") == "http://localhost:443")
        #expect(UrlNormalizer.normalize("127.0.0.1:443") == "http://127.0.0.1:443")
    }

    @Test func trims() {
        #expect(UrlNormalizer.normalize("  api.example.com  ") == "https://api.example.com")
    }

    @Test func nonPrivateIPs() {
        #expect(UrlNormalizer.normalize("172.32.0.1") == "https://172.32.0.1")
        #expect(UrlNormalizer.normalize("8.8.8.8") == "https://8.8.8.8")
    }
}
