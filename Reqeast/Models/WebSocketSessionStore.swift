//
//  WebSocketSessionStore.swift
//  Reqeast
//

import Foundation

class WsEventBridge: WsEventHandler {
    private let store: WebSocketSessionStore

    init(store: WebSocketSessionStore) {
        self.store = store
    }

    func onEvent(event: WsEvent) {
        Task { @MainActor in
            self.store.handleEvent(event)
        }
    }
}

@MainActor
@Observable
class WebSocketSessionStore {
    var isConnected = false
    var isConnecting = false
    var messages: [SocketMessage] = []
    var error: RequestError?
    var selectedProtocol: String?
    var unreadCount: Int = 0

    private var client: WsClient?
    private var autoPingTask: Task<Void, Never>?

    func markRead() {
        unreadCount = 0
    }

    func connect(url: String, headers: [KeyValuePair], subprotocols: [String], timeoutSecs: UInt32, allowInsecureTls: Bool) {
        guard !isConnecting && !isConnected else { return }

        isConnecting = true
        error = nil
        messages.append(.system(String(localized: "Connecting to \(url)...")))


        do {
            let wsClient = try WsClient()
            self.client = wsClient

            let config = WsConfig(
                url: url,
                headers: headers,
                subprotocols: subprotocols,
                timeoutSecs: timeoutSecs,
                allowInsecureTls: allowInsecureTls
            )

            let bridge = WsEventBridge(store: self)
            try wsClient.connect(config: config, handler: bridge)
        } catch {
            isConnecting = false
            let reqError = RequestError.from(error)
            messages.append(.system(String(localized: "Connection failed: \(reqError.message)")))
            self.error = reqError

        }
    }

    func sendText(_ text: String, encoding: DataEncoding) {
        guard let client, isConnected else {
            messages.append(.system(String(localized: "Error: Not connected")))
            return
        }

        let data = text.data(using: .utf8) ?? Data()
        messages.append(SocketMessage(data: data, direction: .sent, encoding: encoding))

        do {
            try client.sendText(text: text)

        } catch {
            let reqError = RequestError.from(error)
            messages.append(.system(String(localized: "Send failed: \(reqError.message)")))

        }
    }

    func sendBinary(_ data: Data, encoding: DataEncoding) {
        guard let client, isConnected else {
            messages.append(.system("Error: Not connected"))
            return
        }

        messages.append(SocketMessage(data: data, direction: .sent, encoding: encoding))

        do {
            try client.sendBinary(data: data)

        } catch {
            let reqError = RequestError.from(error)
            messages.append(.system("Send failed: \(reqError.message)"))

        }
    }

    func ping() {
        guard let client, isConnected else { return }
        do {
            try client.ping(data: Data())
            messages.append(.system(String(localized: "Ping sent")))
        } catch {
            messages.append(.system(String(localized: "Ping failed: \(error.localizedDescription)")))
        }
    }

    func startAutoPing(intervalSeconds: Int) {
        stopAutoPing()
        guard intervalSeconds > 0, isConnected else { return }
        autoPingTask = Task {
            while !Task.isCancelled && self.isConnected {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                guard !Task.isCancelled && self.isConnected else { break }
                self.ping()
            }
        }
    }

    func stopAutoPing() {
        autoPingTask?.cancel()
        autoPingTask = nil
    }

    func disconnect() {
        stopAutoPing()
        if let client {
            try? client.disconnect()
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

    func handleEvent(_ event: WsEvent) {
        switch event {
        case .connected(let proto):
            isConnecting = false
            isConnected = true
            selectedProtocol = proto
            let protoLabel = proto.map { " (protocol: \($0))" } ?? ""
            messages.append(.system(String(localized: "Connected\(protoLabel)")))


        case .textReceived(let text):
            let data = text.data(using: .utf8) ?? Data()
            messages.append(SocketMessage(data: data, direction: .received))
            unreadCount += 1


        case .binaryReceived(let bytes):
            messages.append(SocketMessage(data: Data(bytes), direction: .received))
            unreadCount += 1


        case .pongReceived:
            messages.append(.system(String(localized: "Pong received")))

        case .disconnected(let code, let reason):
            isConnected = false
            isConnecting = false
            client = nil
            stopAutoPing()
            messages.append(.system(String(localized: "Disconnected [\(code)]: \(reason)")))


        case .error(let errorMsg):
            isConnected = false
            isConnecting = false
            client = nil
            stopAutoPing()
            error = RequestError.from(message: errorMsg, kind: .webSocketError)
            messages.append(.system(String(localized: "Error: \(errorMsg)")))

        }
    }
}
