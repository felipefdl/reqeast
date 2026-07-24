//
//  GrpcSessionStore.swift
//  Reqeast
//

import Foundation

class GrpcEventBridge: GrpcEventHandler {
    private let store: GrpcSessionStore

    init(store: GrpcSessionStore) {
        self.store = store
    }

    func onEvent(event: GrpcEvent) {
        Task { @MainActor in
            self.store.handleEvent(event)
        }
    }
}

@MainActor
@Observable
class GrpcSessionStore {
    var isConnected = false
    var isConnecting = false
    var messages: [SocketMessage] = []
    var error: RequestError?
    var unreadCount: Int = 0

    private var client: GrpcClient?

    func markRead() {
        unreadCount = 0
    }

    func startStream(
        config: GrpcConfig,
        descriptorBytes: Data,
        requestBody: String,
        bodyIsHex: Bool
    ) {
        guard !isConnecting && !isConnected else { return }

        // Parse hex with the same FFI path as Rust before preview/connect so odd-length
        // or invalid hex never appears as a "sent" message.
        let initialSent: SocketMessage?
        if requestBody.isEmpty {
            initialSent = nil
        } else {
            do {
                initialSent = try makeSentPreview(body: requestBody, bodyIsHex: bodyIsHex)
            } catch {
                let reqError = RequestError.from(error)
                messages.append(.system(String(localized: "Send failed: \(reqError.message)")))
                self.error = reqError
                return
            }
        }

        isConnecting = true
        error = nil
        messages.append(.system(String(localized: "Connecting to \(config.authority)...")))

        do {
            let grpcClient = try GrpcClient()
            client = grpcClient
            let bridge = GrpcEventBridge(store: self)
            try grpcClient.startStream(
                config: config,
                descriptorBytes: descriptorBytes,
                requestBody: requestBody,
                bodyIsHex: bodyIsHex,
                handler: bridge
            )
            if let initialSent {
                messages.append(initialSent)
            }
        } catch {
            isConnecting = false
            client = nil
            let reqError = RequestError.from(error)
            messages.append(.system(String(localized: "Connection failed: \(reqError.message)")))
            self.error = reqError
        }
    }

    func sendMessage(_ body: String, bodyIsHex: Bool) {
        guard let client, isConnected else {
            messages.append(.system(String(localized: "Error: Not connected")))
            return
        }

        let preview: SocketMessage
        do {
            preview = try makeSentPreview(body: body, bodyIsHex: bodyIsHex)
        } catch {
            let reqError = RequestError.from(error)
            messages.append(.system(String(localized: "Send failed: \(reqError.message)")))
            return
        }

        do {
            try client.sendMessage(body: body, bodyIsHex: bodyIsHex)
            messages.append(preview)
        } catch {
            let reqError = RequestError.from(error)
            messages.append(.system(String(localized: "Send failed: \(reqError.message)")))
        }
    }

    /// Builds a conversation-log preview using `hexToWire` for hex so display matches wire bytes.
    private func makeSentPreview(body: String, bodyIsHex: Bool) throws -> SocketMessage {
        if bodyIsHex {
            let data = try hexToWire(hex: body)
            return SocketMessage(data: data, direction: .sent, encoding: .hex)
        }
        let data = body.data(using: .utf8) ?? Data()
        return SocketMessage(data: data, direction: .sent, encoding: .utf8)
    }

    func halfClose() {
        guard let client, isConnected else {
            messages.append(.system(String(localized: "Error: Not connected")))
            return
        }

        do {
            try client.halfClose()
        } catch {
            let reqError = RequestError.from(error)
            messages.append(.system(String(localized: "Half-close failed: \(reqError.message)")))
        }
    }

    func cancel() {
        guard let client else { return }
        try? client.cancel()
    }

    func disconnect() {
        if let client {
            try? client.cancel()
        }
        client = nil
        isConnected = false
        isConnecting = false
        messages.append(.system(String(localized: "Disconnected")))
    }

    func clear() {
        messages.removeAll()
    }

    // MARK: - Event Handling

    func handleEvent(_ event: GrpcEvent) {
        switch event {
        case .connected:
            isConnecting = false
            isConnected = true
            messages.append(.system(String(localized: "Connected")))

        case .metadataReceived(let headers):
            let summary = headers
                .filter(\.enabled)
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            let label = summary.isEmpty
                ? String(localized: "Metadata received")
                : String(localized: "Metadata received: \(summary)")
            messages.append(.system(label))

        case .messageReceived(let json, let hex, let truncated):
            let data = json.data(using: .utf8) ?? Data()
            messages.append(
                SocketMessage(
                    data: data,
                    direction: .received,
                    encoding: .utf8,
                    wireHex: hex,
                    truncated: truncated
                )
            )
            unreadCount += 1

        case .streamHalfClosed:
            messages.append(.system(String(localized: "Stream half-closed")))

        case .completed(let statusCode, let statusMessage, let trailers):
            isConnected = false
            isConnecting = false
            client = nil
            let trailerSummary = trailers
                .filter(\.enabled)
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            var statusLabel = statusMessage.isEmpty ? "\(statusCode)" : "[\(statusCode)] \(statusMessage)"
            if !trailerSummary.isEmpty {
                statusLabel += " (\(trailerSummary))"
            }
            messages.append(.system(String(localized: "Completed \(statusLabel)")))

        case .error(let errorMsg):
            isConnected = false
            isConnecting = false
            client = nil
            error = RequestError.from(message: errorMsg, kind: .grpcError)
            messages.append(.system(String(localized: "Error: \(errorMsg)")))
        }
    }
}
