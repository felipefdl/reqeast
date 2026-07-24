//
//  GrpcRequestDataTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("GrpcRequestData Model")
struct GrpcRequestDataTests {
    @Test func defaultsAreCorrect() {
        let data = GrpcRequestData()
        #expect(data.authority == "")
        #expect(data.useTls == false)
        #expect(data.allowInsecureTls == false)
        #expect(data.schemaSource == .protoBundle)
        #expect(data.protoBundleId == nil)
        #expect(data.service == "")
        #expect(data.method == "")
        #expect(data.rpcKind == .unary)
        #expect(data.requestBodyJSON == "")
        #expect(data.requestBodyHex == "")
        #expect(data.bodyMode == .json)
        #expect(data.timeoutSeconds == 30)
        #expect(data.deadlineMs == 0)
        #expect(data.metadata.count == 1)
        #expect(data.messageHistory.isEmpty)
    }

    @Test func grpcRequestDataRoundTrip() throws {
        var data = GrpcRequestData()
        data.authority = "localhost:50051"
        data.service = "helloworld.Greeter"
        data.method = "SayHello"
        data.requestBodyJSON = #"{"name":"Reqeast"}"#
        data.rpcKind = .serverStreaming
        data.bodyMode = .hex
        data.schemaSource = .reflection

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(GrpcRequestData.self, from: encoded)

        #expect(decoded.authority == "localhost:50051")
        #expect(decoded.service == "helloworld.Greeter")
        #expect(decoded.method == "SayHello")
        #expect(decoded.requestBodyJSON == #"{"name":"Reqeast"}"#)
        #expect(decoded.rpcKind == .serverStreaming)
        #expect(decoded.bodyMode == .hex)
        #expect(decoded.schemaSource == .reflection)
    }

    @Test func decodesWithoutMessageHistory() throws {
        let json = """
        {
            "authority": "localhost:50051",
            "useTls": false,
            "allowInsecureTls": false,
            "metadata": [],
            "schemaSource": "protoBundle",
            "service": "helloworld.Greeter",
            "method": "SayHello",
            "rpcKind": "unary",
            "requestBodyJSON": "{}",
            "requestBodyHex": "",
            "bodyMode": "json",
            "timeoutSeconds": 30,
            "deadlineMs": 0
        }
        """
        let data = try JSONDecoder().decode(GrpcRequestData.self, from: Data(json.utf8))
        #expect(data.authority == "localhost:50051")
        #expect(data.messageHistory.isEmpty)
    }

    @Test func clampsNegativeTimeoutAndDeadlineOnDecode() throws {
        let json = """
        {
            "authority": "localhost:50051",
            "timeoutSeconds": -1,
            "deadlineMs": -50
        }
        """
        let data = try JSONDecoder().decode(GrpcRequestData.self, from: Data(json.utf8))
        #expect(data.timeoutSeconds == 0)
        #expect(data.deadlineMs == 0)
    }

    @Test func clampsOversizedTimeoutAndDeadlineOnDecode() throws {
        let oversized = UInt64(UInt32.max) + 1
        let json = """
        {
            "authority": "localhost:50051",
            "timeoutSeconds": \(oversized),
            "deadlineMs": \(oversized)
        }
        """
        let data = try JSONDecoder().decode(GrpcRequestData.self, from: Data(json.utf8))
        #expect(data.timeoutSeconds == Int(UInt32.max))
        #expect(data.deadlineMs == Int(UInt32.max))
    }

    @Test func initClampsTimeoutAndDeadline() {
        let data = GrpcRequestData(timeoutSeconds: -5, deadlineMs: Int(UInt64(UInt32.max) + 10))
        #expect(data.timeoutSeconds == 0)
        #expect(data.deadlineMs == Int(UInt32.max))
    }
}