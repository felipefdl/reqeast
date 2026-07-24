//
//  SocketMessageTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("SocketMessage")
struct SocketMessageTests {

    // MARK: - system() factory

    @Test func systemFactoryCreatesSystemDirection() {
        let msg = SocketMessage.system("Connected")
        #expect(msg.direction == .system)
        #expect(msg.systemText == "Connected")
        #expect(msg.data.isEmpty)
    }

    // MARK: - displayText

    @Test func displayTextReturnsSystemText() {
        let msg = SocketMessage.system("Disconnected")
        #expect(msg.displayText == "Disconnected")
    }

    @Test func displayTextReturnsUtf8DecodedString() {
        let msg = SocketMessage(
            data: Data("Hello".utf8),
            direction: .sent,
            encoding: .utf8
        )
        #expect(msg.displayText == "Hello")
    }

    @Test func displayTextFallsBackToHexForInvalidUtf8() {
        let invalidUtf8 = Data([0xFF, 0xFE])
        let msg = SocketMessage(
            data: invalidUtf8,
            direction: .received,
            encoding: .utf8
        )
        #expect(msg.displayText == "FF FE")
    }

    @Test func displayTextReturnsHexForHexEncoding() {
        let msg = SocketMessage(
            data: Data([0x0A, 0x0B, 0x0C]),
            direction: .sent,
            encoding: .hex
        )
        #expect(msg.displayText == "0A 0B 0C")
    }

    @Test func displayTextReturnsBase64ForBase64Encoding() {
        let msg = SocketMessage(
            data: Data("test".utf8),
            direction: .sent,
            encoding: .base64
        )
        #expect(msg.displayText == Data("test".utf8).base64EncodedString())
    }

    // MARK: - hexString

    @Test func hexStringFormat() {
        let msg = SocketMessage(
            data: Data([0xFF, 0x00, 0xAB]),
            direction: .sent
        )
        #expect(msg.hexString == "FF 00 AB")
    }

    // MARK: - Codable

    @Test func codableRoundTrip() throws {
        let msg = SocketMessage(
            data: Data("payload".utf8),
            direction: .sent,
            encoding: .utf8,
            systemText: nil
        )

        let encoded = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(SocketMessage.self, from: encoded)

        #expect(decoded.id == msg.id)
        #expect(decoded.data == msg.data)
        #expect(decoded.direction == msg.direction)
        #expect(decoded.encoding == msg.encoding)
        #expect(decoded.systemText == nil)
    }
}
