//
//  HawkAuthServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("HawkAuthService")
struct HawkAuthServiceTests {
    @Test func sha256WithHawkSpecVector() {
        let header = HawkAuthService.generateHeader(
            url: "http://example.com:8000/resource/1?b=1&a=2",
            method: "GET",
            authId: "dh37fgj492je",
            authKey: "werxhqb98rpaxn39848xrunpaw3489ruxnpa98w4rxn",
            algorithm: .sha256,
            timestamp: 1353832234,
            nonce: "j4h3g2"
        )
        #expect(header != nil)
        #expect(header!.contains("iEc07MfFE4RNate7H3GGRbMSaRnITwkqHaIhFJ1t0DY="))
        #expect(header!.contains(#"id="dh37fgj492je""#))
        #expect(header!.contains(#"ts="1353832234""#))
        #expect(header!.contains(#"nonce="j4h3g2""#))
    }

    @Test func sha512ProducesDifferentMac() {
        let sha256 = HawkAuthService.generateHeader(
            url: "http://example.com:8000/resource/1?b=1&a=2",
            method: "GET",
            authId: "dh37fgj492je",
            authKey: "werxhqb98rpaxn39848xrunpaw3489ruxnpa98w4rxn",
            algorithm: .sha256,
            timestamp: 1353832234,
            nonce: "j4h3g2"
        )
        let sha512 = HawkAuthService.generateHeader(
            url: "http://example.com:8000/resource/1?b=1&a=2",
            method: "GET",
            authId: "dh37fgj492je",
            authKey: "werxhqb98rpaxn39848xrunpaw3489ruxnpa98w4rxn",
            algorithm: .sha512,
            timestamp: 1353832234,
            nonce: "j4h3g2"
        )
        #expect(sha256 != nil)
        #expect(sha512 != nil)
        #expect(sha256 != sha512)
    }

    @Test func invalidUrlReturnsNil() {
        let header = HawkAuthService.generateHeader(
            url: "",
            method: "GET",
            authId: "id",
            authKey: "key",
            algorithm: .sha256,
            timestamp: 1000,
            nonce: "abc"
        )
        #expect(header == nil)
    }

    @Test func httpsDefaultsToPort443() {
        let header = HawkAuthService.generateHeader(
            url: "https://example.com/path",
            method: "GET",
            authId: "testid",
            authKey: "testkey",
            algorithm: .sha256,
            timestamp: 1000000,
            nonce: "testnonce"
        )
        #expect(header != nil)
        let headerExplicit = HawkAuthService.generateHeader(
            url: "https://example.com:443/path",
            method: "GET",
            authId: "testid",
            authKey: "testkey",
            algorithm: .sha256,
            timestamp: 1000000,
            nonce: "testnonce"
        )
        #expect(header == headerExplicit)
    }

    @Test func httpDefaultsToPort80() {
        let header = HawkAuthService.generateHeader(
            url: "http://example.com/path",
            method: "GET",
            authId: "testid",
            authKey: "testkey",
            algorithm: .sha256,
            timestamp: 1000000,
            nonce: "testnonce"
        )
        #expect(header != nil)
        let headerExplicit = HawkAuthService.generateHeader(
            url: "http://example.com:80/path",
            method: "GET",
            authId: "testid",
            authKey: "testkey",
            algorithm: .sha256,
            timestamp: 1000000,
            nonce: "testnonce"
        )
        #expect(header == headerExplicit)
    }

    @Test func outputStartsWithHawkPrefix() {
        let header = HawkAuthService.generateHeader(
            url: "https://api.example.com/v1",
            method: "POST",
            authId: "myid",
            authKey: "mykey",
            algorithm: .sha256,
            timestamp: 999,
            nonce: "n1"
        )
        #expect(header?.hasPrefix("Hawk ") == true)
    }
}
