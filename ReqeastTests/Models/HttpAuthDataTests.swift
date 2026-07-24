//
//  HttpAuthDataTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("HttpAuthData Model")
struct HttpAuthDataTests {
    @Test func defaultInit() {
        let auth = HttpAuthData()
        #expect(auth.jwtAlgorithm == .hs256)
        #expect(auth.jwtSecret == "")
        #expect(auth.jwtPayload == "{\n  \n}")
        #expect(auth.jwtBase64Encoded == false)
        #expect(auth.jwtHeaderPrefix == "Bearer")
        #expect(auth.hawkAuthId == "")
        #expect(auth.hawkAuthKey == "")
        #expect(auth.hawkAlgorithm == .sha256)
        #expect(auth.awsAccessKey == "")
        #expect(auth.awsSecretKey == "")
        #expect(auth.awsRegion == "")
        #expect(auth.awsService == "")
        #expect(auth.awsSessionToken == "")
        #expect(auth.akamaiClientToken == "")
        #expect(auth.akamaiClientSecret == "")
        #expect(auth.akamaiAccessToken == "")
    }

    @Test func codableRoundtrip() throws {
        let auth = HttpAuthData(
            jwtAlgorithm: .hs512,
            jwtSecret: "mysecret",
            jwtPayload: "{\"sub\": \"test\"}",
            jwtBase64Encoded: true,
            jwtHeaderPrefix: "Token",
            hawkAuthId: "hawk-id",
            hawkAuthKey: "hawk-key",
            hawkAlgorithm: .sha512,
            awsAccessKey: "AKID",
            awsSecretKey: "secret",
            awsRegion: "us-east-1",
            awsService: "s3",
            awsSessionToken: "session",
            akamaiClientToken: "ct",
            akamaiClientSecret: "cs",
            akamaiAccessToken: "at"
        )

        let encoded = try JSONEncoder().encode(auth)
        let decoded = try JSONDecoder().decode(HttpAuthData.self, from: encoded)

        #expect(decoded.jwtAlgorithm == .hs512)
        #expect(decoded.jwtSecret == "mysecret")
        #expect(decoded.jwtBase64Encoded == true)
        #expect(decoded.jwtHeaderPrefix == "Token")
        #expect(decoded.hawkAlgorithm == .sha512)
        #expect(decoded.awsRegion == "us-east-1")
        #expect(decoded.akamaiClientToken == "ct")
    }

    @Test func jwtAlgorithmRawValues() {
        #expect(JwtAlgorithm.hs256.rawValue == "HS256")
        #expect(JwtAlgorithm.hs384.rawValue == "HS384")
        #expect(JwtAlgorithm.hs512.rawValue == "HS512")
    }

    @Test func hawkAlgorithmRawValues() {
        #expect(HawkAlgorithm.sha256.rawValue == "sha256")
        #expect(HawkAlgorithm.sha512.rawValue == "sha512")
    }
}
