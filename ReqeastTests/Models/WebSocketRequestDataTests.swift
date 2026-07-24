//
//  WebSocketRequestDataTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("WebSocketRequestData Model")
struct WebSocketRequestDataTests {
    @Test func defaultsAreCorrect() {
        let data = WebSocketRequestData()
        #expect(data.url == "")
        #expect(data.subprotocols == "")
        #expect(data.encoding == .utf8)
        #expect(data.allowInsecureTls == false)
        #expect(data.timeoutSeconds == 30)
        #expect(data.headers.count == 1)
    }

    @Test func codableRoundtrip() throws {
        var data = WebSocketRequestData()
        data.url = "wss://echo.websocket.org"
        data.subprotocols = "graphql-ws"
        data.encoding = .hex
        data.allowInsecureTls = true
        data.timeoutSeconds = 60

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(WebSocketRequestData.self, from: encoded)

        #expect(decoded.url == "wss://echo.websocket.org")
        #expect(decoded.subprotocols == "graphql-ws")
        #expect(decoded.encoding == .hex)
        #expect(decoded.allowInsecureTls == true)
        #expect(decoded.timeoutSeconds == 60)
    }
}
