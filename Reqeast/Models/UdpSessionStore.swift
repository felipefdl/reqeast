//
//  UdpSessionStore.swift
//  Reqeast
//

import Foundation

class UdpEventBridge: UdpEventHandler {
    private let store: UdpSessionStore

    init(store: UdpSessionStore) {
        self.store = store
    }

    func onEvent(event: UdpEvent) {
        Task { @MainActor in
            self.store.handleEvent(event)
        }
    }
}

@MainActor
@Observable
class UdpSessionStore {
    var isListening = false
    var isSendingOneShot = false
    var messages: [SocketMessage] = []
    var error: RequestError?
    var unreadCount: Int = 0

    private var client: UdpClient?

    func markRead() {
        unreadCount = 0
    }
    private var targetHost: String = ""
    private var targetPort: Int = 0

    func start(host: String, port: Int, bindPort: Int?) {
        guard !isListening else { return }

        targetHost = host
        targetPort = port
        error = nil

        let bindLabel = bindPort.map { " (bind :\($0))" } ?? ""
        messages.append(.system(String(localized: "Starting UDP to \(host):\(port)\(bindLabel)...")))


        do {
            let udpClient = try UdpClient()
            self.client = udpClient

            let config = UdpConfig(
                host: host,
                port: UInt16(port),
                bindPort: bindPort.map { UInt16($0) },
                timeoutSecs: 30
            )

            let bridge = UdpEventBridge(store: self)
            try udpClient.start(config: config, handler: bridge)
            isListening = true
            messages.append(.system(String(localized: "Ready -- \(host):\(port)")))

        } catch {
            let reqError = RequestError.from(error)
            messages.append(.system(String(localized: "Failed: \(reqError.message)")))
            self.error = reqError

        }
    }

    func send(data: Data, encoding: DataEncoding) {
        guard let client, isListening else {
            messages.append(.system(String(localized: "Error: Not started")))
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

    func sendOneShot(host: String, port: Int, bindPort: Int?, data: Data, encoding: DataEncoding, keepConnected: Bool) {
        guard !isListening && !isSendingOneShot else { return }

        isSendingOneShot = true

        Task {
            start(host: host, port: port, bindPort: bindPort)

            guard isListening else {
                isSendingOneShot = false
                return
            }

            send(data: data, encoding: encoding)

            if !keepConnected {
                try? await Task.sleep(for: .milliseconds(500))
                stop()
            }

            isSendingOneShot = false
        }
    }

    func stop() {
        if let client {
            try? client.stop()
        }
        client = nil
        isListening = false
        messages.append(.system(String(localized: "Stopped")))

    }

    func clear() {
        messages.removeAll()
    }

    // MARK: - Event Handling

    func handleEvent(_ event: UdpEvent) {
        switch event {
        case .dataReceived(let data, let fromAddr):
            messages.append(.system(String(localized: "Received \(data.count) bytes from \(fromAddr)")))
            let message = SocketMessage(data: Data(data), direction: .received)
            messages.append(message)
            unreadCount += 1


        case .error(let errorMsg):
            error = RequestError.from(message: errorMsg, kind: .connectionFailed)
            messages.append(.system(String(localized: "Error: \(errorMsg)")))

        }
    }
}
