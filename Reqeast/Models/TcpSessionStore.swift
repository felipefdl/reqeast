//
//  TcpSessionStore.swift
//  Reqeast
//

import Foundation

class TcpEventBridge: TcpEventHandler {
    private let store: TcpSessionStore

    init(store: TcpSessionStore) {
        self.store = store
    }

    func onEvent(event: TcpEvent) {
        Task { @MainActor in
            self.store.handleEvent(event)
        }
    }
}

@MainActor
@Observable
class TcpSessionStore {
    var isConnected = false
    var isConnecting = false
    var isSendingOneShot = false
    var messages: [SocketMessage] = []
    var error: RequestError?
    var unreadCount: Int = 0

    private var client: TcpClient?
    private var onConnectedContinuation: CheckedContinuation<Bool, Never>?

    func markRead() {
        unreadCount = 0
    }

    func connect(host: String, port: Int, useTls: Bool) {
        guard !isConnecting && !isConnected else { return }

        isConnecting = true
        error = nil
        let label = useTls ? "TLS" : "TCP"
        messages.append(.system(String(localized: "Connecting to \(host):\(port) (\(label))...")))


        do {
            let tcpClient = try TcpClient()
            self.client = tcpClient

            let config = TcpConfig(
                host: host,
                port: UInt16(port),
                useTls: useTls,
                allowInsecureTls: false,
                timeoutSecs: 30
            )

            let bridge = TcpEventBridge(store: self)
            try tcpClient.connect(config: config, handler: bridge)
        } catch {
            isConnecting = false
            let reqError = RequestError.from(error)
            messages.append(.system(String(localized: "Connection failed: \(reqError.message)")))
            self.error = reqError

        }
    }

    func send(data: Data, encoding: DataEncoding) {
        guard let client, isConnected else {
            messages.append(.system(String(localized: "Error: Not connected")))
            return
        }

        let message = SocketMessage(data: data, direction: .sent, encoding: encoding)
        messages.append(message)

        do {
            try client.send(data: data)

        } catch {
            let reqError = RequestError.from(error)
            messages.append(.system(String(localized: "Send failed: \(reqError.message)")))

        }
    }

    func sendOneShot(host: String, port: Int, useTls: Bool, data: Data, encoding: DataEncoding, keepConnected: Bool) {
        guard !isConnecting && !isConnected && !isSendingOneShot else { return }

        isSendingOneShot = true

        Task {
            connect(host: host, port: port, useTls: useTls)

            let connected = await withCheckedContinuation { continuation in
                self.onConnectedContinuation = continuation
            }

            guard connected else {
                isSendingOneShot = false
                return
            }

            send(data: data, encoding: encoding)

            if !keepConnected {
                try? await Task.sleep(for: .milliseconds(500))
                disconnect()
            }

            isSendingOneShot = false
        }
    }

    func disconnect() {
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

    func handleEvent(_ event: TcpEvent) {
        switch event {
        case .connected:
            isConnecting = false
            isConnected = true
            messages.append(.system(String(localized: "Connected")))

            onConnectedContinuation?.resume(returning: true)
            onConnectedContinuation = nil

        case .dataReceived(let data):
            let message = SocketMessage(data: Data(data), direction: .received)
            messages.append(message)
            unreadCount += 1


        case .disconnected(let reason):
            isConnected = false
            isConnecting = false
            client = nil
            messages.append(.system(String(localized: "Disconnected: \(reason)")))

            onConnectedContinuation?.resume(returning: false)
            onConnectedContinuation = nil

        case .error(let errorMsg):
            isConnected = false
            isConnecting = false
            client = nil
            error = RequestError.from(message: errorMsg, kind: .connectionFailed)
            messages.append(.system(String(localized: "Error: \(errorMsg)")))

            onConnectedContinuation?.resume(returning: false)
            onConnectedContinuation = nil
        }
    }
}
