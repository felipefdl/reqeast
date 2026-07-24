//
//  AwsSignatureServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("AwsSignatureService")
struct AwsSignatureServiceTests {
    private static let testDate: Date = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.date(from: "2015-08-30T12:36:00Z")!
    }()

    @Test func authorizationHeaderFormat() {
        let headers = AwsSignatureService.generateHeaders(
            url: "https://example.amazonaws.com/",
            method: "GET",
            headers: [],
            body: nil,
            accessKey: "AKIDEXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            service: "service",
            sessionToken: "",
            date: Self.testDate
        )
        #expect(headers != nil)
        let authHeader = headers!.first { $0.0 == "Authorization" }
        #expect(authHeader != nil)
        #expect(authHeader!.1.hasPrefix("AWS4-HMAC-SHA256"))
        #expect(authHeader!.1.contains("Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request"))
        #expect(authHeader!.1.contains("SignedHeaders="))
        #expect(authHeader!.1.contains("Signature="))
    }

    @Test func amzDateHeaderPresent() {
        let headers = AwsSignatureService.generateHeaders(
            url: "https://example.amazonaws.com/",
            method: "GET",
            headers: [],
            body: nil,
            accessKey: "AKIDEXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            service: "service",
            sessionToken: "",
            date: Self.testDate
        )
        let amzDate = headers!.first { $0.0 == "x-amz-date" }
        #expect(amzDate?.1 == "20150830T123600Z")
    }

    @Test func emptyBodyHash() {
        let headers = AwsSignatureService.generateHeaders(
            url: "https://example.amazonaws.com/",
            method: "GET",
            headers: [],
            body: nil,
            accessKey: "AKIDEXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            service: "service",
            sessionToken: "",
            date: Self.testDate
        )
        let contentHash = headers!.first { $0.0 == "x-amz-content-sha256" }
        #expect(contentHash?.1 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func sessionTokenIncluded() {
        let headers = AwsSignatureService.generateHeaders(
            url: "https://example.amazonaws.com/",
            method: "GET",
            headers: [],
            body: nil,
            accessKey: "AKIDEXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            service: "service",
            sessionToken: "my-session-token",
            date: Self.testDate
        )
        let tokenHeader = headers!.first { $0.0 == "x-amz-security-token" }
        #expect(tokenHeader?.1 == "my-session-token")
    }

    @Test func sessionTokenExcludedWhenEmpty() {
        let headers = AwsSignatureService.generateHeaders(
            url: "https://example.amazonaws.com/",
            method: "GET",
            headers: [],
            body: nil,
            accessKey: "AKIDEXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            service: "service",
            sessionToken: "",
            date: Self.testDate
        )
        let tokenHeader = headers!.first { $0.0 == "x-amz-security-token" }
        #expect(tokenHeader == nil)
    }

    @Test func invalidUrlReturnsNil() {
        let headers = AwsSignatureService.generateHeaders(
            url: "",
            method: "GET",
            headers: [],
            body: nil,
            accessKey: "AK",
            secretKey: "SK",
            region: "us-east-1",
            service: "s3",
            sessionToken: "",
            date: Self.testDate
        )
        #expect(headers == nil)
    }
}
