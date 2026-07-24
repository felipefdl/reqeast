//
//  UdpRequestDataTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("UdpRequestData Model")
struct UdpRequestDataTests {
    @Test func defaultsAreCorrect() {
        let data = UdpRequestData()
        #expect(data.host == "")
        #expect(data.port == 8080)
        #expect(data.bindPort == nil)
        #expect(data.encoding == .utf8)
        #expect(data.lineEnding == .none)
        #expect(data.timeoutSeconds == 10)
        #expect(data.keepConnected == true)
        #expect(data.messageHistory.isEmpty)
    }

    @Test func codableRoundtrip() throws {
        var data = UdpRequestData()
        data.host = "192.168.1.1"
        data.port = 9000
        data.bindPort = 5000
        data.encoding = .base64
        data.lineEnding = .crlf
        data.timeoutSeconds = 30
        data.keepConnected = false

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(UdpRequestData.self, from: encoded)

        #expect(decoded.host == "192.168.1.1")
        #expect(decoded.port == 9000)
        #expect(decoded.bindPort == 5000)
        #expect(decoded.encoding == .base64)
        #expect(decoded.lineEnding == .crlf)
        #expect(decoded.timeoutSeconds == 30)
        #expect(decoded.keepConnected == false)
    }

    @Test func backwardCompatMissingLineEndingDefaultsToNone() throws {
        let json = """
        {
            "host": "localhost",
            "port": 8080,
            "encoding": "utf8",
            "timeoutSeconds": 10
        }
        """
        let data = try JSONDecoder().decode(UdpRequestData.self, from: Data(json.utf8))
        #expect(data.lineEnding == .none)
    }

    @Test func backwardCompatMissingKeepConnectedDefaultsToTrue() throws {
        let json = """
        {
            "host": "localhost",
            "port": 8080,
            "encoding": "utf8",
            "lineEnding": "lf",
            "timeoutSeconds": 10
        }
        """
        let data = try JSONDecoder().decode(UdpRequestData.self, from: Data(json.utf8))
        #expect(data.keepConnected == true)
    }
}
