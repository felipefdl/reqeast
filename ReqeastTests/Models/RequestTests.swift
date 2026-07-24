//
//  RequestTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("Request Model")
struct RequestTests {
    @Test func httpRequestCreatesHttpData() {
        let request = Request(projectId: UUID(), name: "Test", type: .http)
        #expect(request.httpData != nil)
        #expect(request.tcpData == nil)
        #expect(request.udpData == nil)
    }

    @Test func tcpRequestCreatesTcpData() {
        let request = Request(projectId: UUID(), name: "Test", type: .tcp)
        #expect(request.tcpData != nil)
        #expect(request.tcpData?.useTls == false)
    }

    @Test func udpRequestCreatesUdpData() {
        let request = Request(projectId: UUID(), name: "Test", type: .udp)
        #expect(request.udpData != nil)
    }

    @Test func webSocketRequestCreatesWebSocketData() {
        let request = Request(projectId: UUID(), name: "Test", type: .webSocket)
        #expect(request.webSocketData != nil)
        #expect(request.httpData == nil)
        #expect(request.tcpData == nil)
    }

    @Test func sseRequestCreatesSseData() {
        let request = Request(projectId: UUID(), name: "Test", type: .sse)
        #expect(request.sseData != nil)
        #expect(request.httpData == nil)
        #expect(request.webSocketData == nil)
    }

    @Test func grpcRequestCreatesGrpcData() {
        let request = Request(projectId: UUID(), name: "Test", type: .grpc)
        #expect(request.grpcData != nil)
        #expect(request.httpData == nil)
        #expect(request.tcpData == nil)
        #expect(request.grpcData?.rpcKind == .unary)
    }

    @Test func requestTypeLocalizedNames() {
        #expect(RequestType.http.localizedName == "HTTP")
        #expect(RequestType.tcp.localizedName == "TCP")
        #expect(RequestType.udp.localizedName == "UDP")
        #expect(RequestType.webSocket.localizedName == "WebSocket")
        #expect(RequestType.sse.localizedName == "SSE")
        #expect(RequestType.grpc.localizedName == "gRPC")
    }

    @Test func requestTypeIcons() {
        #expect(RequestType.http.iconName == "arrow.up.arrow.down")
        #expect(RequestType.tcp.iconName == "cable.connector")
        #expect(RequestType.webSocket.iconName == "arrow.left.arrow.right")
        #expect(RequestType.sse.iconName == "antenna.radiowaves.left.and.right")
        #expect(RequestType.grpc.iconName == "arrow.up.right.and.arrow.down.left")
    }

    // MARK: - MessageHistoryEntry

    @Test func messageHistoryEntryRoundTrip() throws {
        let entry = MessageHistoryEntry(text: "hello", encoding: .utf8)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(MessageHistoryEntry.self, from: data)
        #expect(decoded.text == "hello")
        #expect(decoded.encoding == .utf8)
        #expect(decoded.id == entry.id)
    }

    @Test func messageHistoryEntryHexEncoding() throws {
        let entry = MessageHistoryEntry(text: "FF00AB", encoding: .hex)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(MessageHistoryEntry.self, from: data)
        #expect(decoded.encoding == .hex)
        #expect(decoded.text == "FF00AB")
    }

    // MARK: - Backward Compatibility

    @Test func tcpRequestDataDecodesWithoutMessageHistory() throws {
        let json = """
        {
            "host": "localhost",
            "port": 8080,
            "useTls": false,
            "allowInsecureTls": false,
            "sessionMode": "persistent",
            "encoding": "utf8",
            "timeoutSeconds": 30
        }
        """
        let data = try JSONDecoder().decode(TcpRequestData.self, from: Data(json.utf8))
        #expect(data.host == "localhost")
        #expect(data.port == 8080)
        #expect(data.messageHistory.isEmpty)
    }

    @Test func udpRequestDataDecodesWithoutMessageHistory() throws {
        let json = """
        {
            "host": "localhost",
            "port": 9090,
            "encoding": "utf8",
            "timeoutSeconds": 10
        }
        """
        let data = try JSONDecoder().decode(UdpRequestData.self, from: Data(json.utf8))
        #expect(data.host == "localhost")
        #expect(data.port == 9090)
        #expect(data.messageHistory.isEmpty)
    }

    @Test func tcpRequestDataDecodesWithMessageHistory() throws {
        let json = """
        {
            "host": "localhost",
            "port": 8080,
            "useTls": false,
            "allowInsecureTls": false,
            "sessionMode": "persistent",
            "encoding": "utf8",
            "timeoutSeconds": 30,
            "messageHistory": [
                {
                    "id": "00000000-0000-0000-0000-000000000001",
                    "text": "ping",
                    "encoding": "utf8",
                    "timestamp": 0
                }
            ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let data = try decoder.decode(TcpRequestData.self, from: Data(json.utf8))
        #expect(data.messageHistory.count == 1)
        #expect(data.messageHistory[0].text == "ping")
    }
}
