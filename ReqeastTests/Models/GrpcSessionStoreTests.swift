//
//  GrpcSessionStoreTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("GrpcSessionStore")
@MainActor
struct GrpcSessionStoreTests {

    // MARK: - Connection state

    @Test func connectedSetsConnectedState() {
        let store = GrpcSessionStore()
        store.handleEvent(.connected)

        #expect(store.isConnected)
        #expect(!store.isConnecting)
        #expect(store.messages.last?.displayText == String(localized: "Connected"))
    }

    @Test func completedClearsConnectionState() {
        let store = GrpcSessionStore()
        store.handleEvent(.connected)
        store.handleEvent(.completed(statusCode: 0, statusMessage: "", trailers: []))

        #expect(!store.isConnected)
        #expect(!store.isConnecting)
    }

    @Test func errorClearsConnectionAndSetsGrpcError() {
        let store = GrpcSessionStore()
        store.handleEvent(.connected)
        store.handleEvent(.error(error: "stream failed"))

        #expect(!store.isConnected)
        #expect(store.error?.kind == .grpcError)
        #expect(store.error?.message == "stream failed")
        #expect(store.messages.last?.isError == true)
    }

    // MARK: - MessageReceived → ConversationLog

    @Test func messageReceivedAppendsSocketMessageWithJsonAndHex() {
        let store = GrpcSessionStore()
        store.handleEvent(.messageReceived(json: #"{"name":"Reqeast"}"#, hex: "0A 05", truncated: false))

        #expect(store.messages.count == 1)
        let message = store.messages[0]
        #expect(message.direction == .received)
        #expect(message.displayText.contains("Reqeast"))
        #expect(message.wireHex == "0A 05")
        #expect(message.truncated == false)
        #expect(store.unreadCount == 1)
    }

    @Test func messageReceivedIncrementsUnreadCount() {
        let store = GrpcSessionStore()
        store.handleEvent(.messageReceived(json: "{}", hex: "", truncated: false))
        store.handleEvent(.messageReceived(json: "{}", hex: "", truncated: false))
        #expect(store.unreadCount == 2)

        store.markRead()
        #expect(store.unreadCount == 0)
    }

    // MARK: - Stream lifecycle events

    @Test func metadataReceivedAppendsSystemMessage() {
        let store = GrpcSessionStore()
        store.handleEvent(.metadataReceived(headers: [
            KeyValuePair(key: "content-type", value: "application/grpc", enabled: true),
        ]))

        #expect(store.messages.count == 1)
        #expect(store.messages[0].direction == .system)
        #expect(store.messages[0].displayText.contains("content-type"))
    }

    @Test func streamHalfClosedAppendsSystemMessage() {
        let store = GrpcSessionStore()
        store.handleEvent(.streamHalfClosed)

        #expect(store.messages.last?.displayText == String(localized: "Stream half-closed"))
    }

    @Test func completedAppendsStatusSystemMessage() {
        let store = GrpcSessionStore()
        store.handleEvent(.completed(statusCode: 0, statusMessage: "OK", trailers: []))

        #expect(store.messages.last?.displayText.contains("0") == true)
        #expect(store.messages.last?.displayText.contains("OK") == true)
    }

    // MARK: - Commands

    @Test func sendMessageWhenNotConnectedAppendsError() {
        let store = GrpcSessionStore()
        store.sendMessage(#"{"name":"test"}"#, bodyIsHex: false)

        #expect(store.messages.count == 1)
        #expect(store.messages[0].isError)
        #expect(store.messages[0].displayText.contains("Not connected"))
    }

    @Test func startStreamRejectsOddLengthHexWithoutSentPreview() {
        let store = GrpcSessionStore()
        let config = GrpcConfig(
            authority: "127.0.0.1:1",
            useTls: false,
            allowInsecureTls: false,
            metadata: [],
            service: "helloworld.Greeter",
            method: "SayHello",
            rpcKind: .clientStreaming,
            deadlineMs: 0,
            timeoutSecs: 1
        )

        store.startStream(
            config: config,
            descriptorBytes: Data([0x0A]),
            requestBody: "0a3",
            bodyIsHex: true
        )

        #expect(!store.isConnecting)
        #expect(!store.isConnected)
        #expect(store.error != nil)
        #expect(store.messages.contains { $0.isError })
        #expect(!store.messages.contains { $0.direction == .sent })
    }

    @Test func sendMessageRejectsOddLengthHexWhenConnected() {
        let store = GrpcSessionStore()
        store.handleEvent(.connected)
        let beforeCount = store.messages.count

        store.sendMessage("0a3", bodyIsHex: true)

        #expect(store.messages.count == beforeCount + 1)
        #expect(store.messages.last?.isError == true)
        #expect(!store.messages.contains { $0.direction == .sent })
    }

    @Test func halfCloseWhenNotConnectedAppendsError() {
        let store = GrpcSessionStore()
        store.halfClose()

        #expect(store.messages.count == 1)
        #expect(store.messages[0].isError)
    }

    @Test func disconnectAppendsDisconnectedMessage() {
        let store = GrpcSessionStore()
        store.handleEvent(.connected)
        store.disconnect()

        #expect(!store.isConnected)
        #expect(store.messages.last?.displayText == String(localized: "Disconnected"))
    }

    @Test func clearRemovesAllMessages() {
        let store = GrpcSessionStore()
        store.handleEvent(.connected)
        store.handleEvent(.messageReceived(json: "{}", hex: "", truncated: false))
        store.clear()

        #expect(store.messages.isEmpty)
    }

    // MARK: - SessionRegistry

    @Test func sessionRegistryTracksGrpcUnreadAndActivity() {
        let registry = SessionRegistry.shared
        let requestId = UUID()

        let store = registry.grpcSession(for: requestId)
        store.handleEvent(.connected)
        store.handleEvent(.messageReceived(json: "{}", hex: "", truncated: false))

        #expect(registry.unreadCount(for: requestId) == 1)
        #expect(registry.hasActivity(for: requestId))

        registry.markRead(for: requestId)
        #expect(store.unreadCount == 0)
    }

    @Test func sessionRegistryRemoveSessionDisconnectsGrpc() {
        let registry = SessionRegistry.shared
        let requestId = UUID()

        let store = registry.grpcSession(for: requestId)
        store.handleEvent(.connected)
        registry.removeSession(for: requestId)

        #expect(!store.isConnected)
        #expect(store.messages.last?.displayText == String(localized: "Disconnected"))
    }
}