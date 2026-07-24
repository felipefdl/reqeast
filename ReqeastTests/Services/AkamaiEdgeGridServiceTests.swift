//
//  AkamaiEdgeGridServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("AkamaiEdgeGridService")
struct AkamaiEdgeGridServiceTests {
    private static let fixedTimestamp = "20240101T12:00:00+0000"
    private static let fixedNonce = "test-nonce-1234"

    @Test func headerStartsWithEG1Prefix() {
        let header = AkamaiEdgeGridService.generateHeader(
            url: "https://akaa-baseurl.luna.akamaiapis.net/path",
            method: "GET",
            body: nil,
            clientToken: "akab-client-token",
            clientSecret: "c2VjcmV0",
            accessToken: "akab-access-token",
            timestamp: Self.fixedTimestamp,
            nonce: Self.fixedNonce
        )
        #expect(header != nil)
        #expect(header!.hasPrefix("EG1-HMAC-SHA256 client_token=akab-client-token;"))
    }

    @Test func headerContainsAllFields() {
        let header = AkamaiEdgeGridService.generateHeader(
            url: "https://akaa-baseurl.luna.akamaiapis.net/path",
            method: "GET",
            body: nil,
            clientToken: "akab-client-token",
            clientSecret: "c2VjcmV0",
            accessToken: "akab-access-token",
            timestamp: Self.fixedTimestamp,
            nonce: Self.fixedNonce
        )!
        #expect(header.contains("client_token=akab-client-token"))
        #expect(header.contains("access_token=akab-access-token"))
        #expect(header.contains("timestamp=\(Self.fixedTimestamp)"))
        #expect(header.contains("nonce=\(Self.fixedNonce)"))
        #expect(header.contains("signature="))
    }

    @Test func postWithBodyProducesDifferentSignature() {
        let getHeader = AkamaiEdgeGridService.generateHeader(
            url: "https://akaa-baseurl.luna.akamaiapis.net/path",
            method: "GET",
            body: nil,
            clientToken: "ct",
            clientSecret: "cs",
            accessToken: "at",
            timestamp: Self.fixedTimestamp,
            nonce: Self.fixedNonce
        )
        let postHeader = AkamaiEdgeGridService.generateHeader(
            url: "https://akaa-baseurl.luna.akamaiapis.net/path",
            method: "POST",
            body: Data("{\"key\":\"value\"}".utf8),
            clientToken: "ct",
            clientSecret: "cs",
            accessToken: "at",
            timestamp: Self.fixedTimestamp,
            nonce: Self.fixedNonce
        )
        #expect(getHeader != nil)
        #expect(postHeader != nil)
        #expect(getHeader != postHeader)
    }

    @Test func getBodyHashIsEmpty() {
        // GET requests should not include a body hash, so the signature
        // with nil body and with non-nil body should be the same for GET
        let withoutBody = AkamaiEdgeGridService.generateHeader(
            url: "https://akaa-baseurl.luna.akamaiapis.net/path",
            method: "GET",
            body: nil,
            clientToken: "ct",
            clientSecret: "cs",
            accessToken: "at",
            timestamp: Self.fixedTimestamp,
            nonce: Self.fixedNonce
        )
        let withBody = AkamaiEdgeGridService.generateHeader(
            url: "https://akaa-baseurl.luna.akamaiapis.net/path",
            method: "GET",
            body: Data("some body".utf8),
            clientToken: "ct",
            clientSecret: "cs",
            accessToken: "at",
            timestamp: Self.fixedTimestamp,
            nonce: Self.fixedNonce
        )
        #expect(withoutBody == withBody)
    }

    @Test func invalidUrlReturnsNil() {
        let header = AkamaiEdgeGridService.generateHeader(
            url: "",
            method: "GET",
            body: nil,
            clientToken: "ct",
            clientSecret: "cs",
            accessToken: "at",
            timestamp: Self.fixedTimestamp,
            nonce: Self.fixedNonce
        )
        #expect(header == nil)
    }

    @Test func deterministicWithSameInputs() {
        let first = AkamaiEdgeGridService.generateHeader(
            url: "https://api.example.com/v1",
            method: "POST",
            body: Data("hello".utf8),
            clientToken: "ct",
            clientSecret: "secret-key",
            accessToken: "at",
            timestamp: Self.fixedTimestamp,
            nonce: Self.fixedNonce
        )
        let second = AkamaiEdgeGridService.generateHeader(
            url: "https://api.example.com/v1",
            method: "POST",
            body: Data("hello".utf8),
            clientToken: "ct",
            clientSecret: "secret-key",
            accessToken: "at",
            timestamp: Self.fixedTimestamp,
            nonce: Self.fixedNonce
        )
        #expect(first == second)
    }
}
