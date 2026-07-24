//
//  JwtAuthServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("JwtAuthService")
struct JwtAuthServiceTests {
    @Test func hs256ProducesValidJwt() {
        let token = JwtAuthService.generateToken(
            algorithm: .hs256, secret: "secret", payload: "{}", base64Encoded: false
        )
        #expect(token != nil)
        #expect(token?.split(separator: ".").count == 3)
    }

    @Test func hs384ProducesValidJwt() {
        let token = JwtAuthService.generateToken(
            algorithm: .hs384, secret: "secret", payload: "{}", base64Encoded: false
        )
        #expect(token != nil)
        #expect(token?.split(separator: ".").count == 3)
    }

    @Test func hs512ProducesValidJwt() {
        let token = JwtAuthService.generateToken(
            algorithm: .hs512, secret: "secret", payload: "{}", base64Encoded: false
        )
        #expect(token != nil)
        #expect(token?.split(separator: ".").count == 3)
    }

    @Test func hs256HeaderContainsAlgAndTyp() {
        let token = JwtAuthService.generateToken(
            algorithm: .hs256, secret: "secret", payload: "{}", base64Encoded: false
        )!
        let headerB64 = String(token.split(separator: ".")[0])
        // Restore base64url to standard base64
        var base64 = headerB64.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        let data = Data(base64Encoded: base64)!
        let header = String(data: data, encoding: .utf8)!
        #expect(header.contains("\"alg\":\"HS256\""))
        #expect(header.contains("\"typ\":\"JWT\""))
    }

    @Test func base64EncodedSecretProducesToken() {
        let secret = Data("my-secret".utf8).base64EncodedString()
        let token = JwtAuthService.generateToken(
            algorithm: .hs256, secret: secret, payload: "{}", base64Encoded: true
        )
        #expect(token != nil)
        #expect(token?.split(separator: ".").count == 3)
    }

    @Test func invalidBase64SecretReturnsNil() {
        let token = JwtAuthService.generateToken(
            algorithm: .hs256, secret: "not-valid-base64!!!", payload: "{}", base64Encoded: true
        )
        #expect(token == nil)
    }
}
