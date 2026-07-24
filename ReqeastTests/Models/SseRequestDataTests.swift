//
//  SseRequestDataTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("SseRequestData Model")
struct SseRequestDataTests {
    @Test func defaultsAreCorrect() {
        let data = SseRequestData()
        #expect(data.url == "")
        #expect(data.sslVerify == true)
        #expect(data.timeoutSeconds == 0)
        #expect(data.headers.count == 1)
    }

    @Test func codableRoundtrip() throws {
        var data = SseRequestData()
        data.url = "https://example.com/events"
        data.sslVerify = false
        data.timeoutSeconds = 120

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(SseRequestData.self, from: encoded)

        #expect(decoded.url == "https://example.com/events")
        #expect(decoded.sslVerify == false)
        #expect(decoded.timeoutSeconds == 120)
    }
}
