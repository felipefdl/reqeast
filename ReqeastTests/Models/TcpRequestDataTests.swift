//
//  TcpRequestDataTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("TcpRequestData Model")
struct TcpRequestDataTests {
    @Test func defaultsAreCorrect() {
        let data = TcpRequestData()
        #expect(data.host == "")
        #expect(data.port == 80)
        #expect(data.useTls == false)
        #expect(data.allowInsecureTls == false)
        #expect(data.sessionMode == .persistent)
        #expect(data.encoding == .utf8)
        #expect(data.lineEnding == .lf)
        #expect(data.timeoutSeconds == 30)
        #expect(data.keepConnected == true)
        #expect(data.messageHistory.isEmpty)
    }

    @Test func codableRoundtrip() throws {
        var data = TcpRequestData()
        data.host = "example.com"
        data.port = 443
        data.useTls = true
        data.allowInsecureTls = true
        data.sessionMode = .oneShot
        data.encoding = .hex
        data.lineEnding = .crlf
        data.timeoutSeconds = 60
        data.keepConnected = false

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(TcpRequestData.self, from: encoded)

        #expect(decoded.host == "example.com")
        #expect(decoded.port == 443)
        #expect(decoded.useTls == true)
        #expect(decoded.allowInsecureTls == true)
        #expect(decoded.sessionMode == .oneShot)
        #expect(decoded.encoding == .hex)
        #expect(decoded.lineEnding == .crlf)
        #expect(decoded.timeoutSeconds == 60)
        #expect(decoded.keepConnected == false)
    }

    @Test func backwardCompatMissingLineEndingDefaultsToLf() throws {
        let json = """
        {
            "host": "localhost",
            "port": 80,
            "useTls": false,
            "allowInsecureTls": false,
            "sessionMode": "persistent",
            "encoding": "utf8",
            "timeoutSeconds": 30
        }
        """
        let data = try JSONDecoder().decode(TcpRequestData.self, from: Data(json.utf8))
        #expect(data.lineEnding == .lf)
    }

    @Test func backwardCompatMissingKeepConnectedDefaultsToTrue() throws {
        let json = """
        {
            "host": "localhost",
            "port": 80,
            "useTls": false,
            "allowInsecureTls": false,
            "sessionMode": "persistent",
            "encoding": "utf8",
            "lineEnding": "none",
            "timeoutSeconds": 30
        }
        """
        let data = try JSONDecoder().decode(TcpRequestData.self, from: Data(json.utf8))
        #expect(data.keepConnected == true)
    }

    @Test func lineEndingBytes() {
        #expect(LineEnding.none.bytes == Data())
        #expect(LineEnding.lf.bytes == Data([0x0A]))
        #expect(LineEnding.crlf.bytes == Data([0x0D, 0x0A]))
    }
}
