//
//  SseSessionStore.swift
//  Reqeast
//

import Foundation

class SseEventBridge: SseEventHandler {
    private let store: SseSessionStore

    init(store: SseSessionStore) {
        self.store = store
    }

    func onEvent(event: SseEvent) {
        Task { @MainActor in
            self.store.handleEvent(event)
        }
    }
}

@MainActor
@Observable
class SseSessionStore {
    var isConnected = false
    var isConnecting = false
    var events: [SseEventEntry] = []
    var error: RequestError?
    var lastEventId: String?
    var unreadCount: Int = 0

    private var client: SseClient?

    func markRead() {
        unreadCount = 0
    }

    func connect(url: String, headers: [KeyValuePair], sslVerify: Bool, timeoutSecs: UInt32, lastEventId: String?) {
        guard !isConnecting && !isConnected else { return }

        isConnecting = true
        error = nil
        events.append(.system(String(localized: "Connecting to \(url)...")))


        do {
            let sseClient = try SseClient()
            self.client = sseClient

            let config = SseConfig(
                url: url,
                headers: headers,
                timeoutSecs: timeoutSecs,
                sslVerify: sslVerify,
                lastEventId: lastEventId
            )

            let bridge = SseEventBridge(store: self)
            try sseClient.connect(config: config, handler: bridge)
        } catch {
            isConnecting = false
            let reqError = RequestError.from(error)
            events.append(.system(String(localized: "Connection failed: \(reqError.message)")))
            self.error = reqError

        }
    }

    func disconnect() {
        if let client {
            try? client.disconnect()
        }
        client = nil
        isConnected = false
        isConnecting = false
        events.append(.system(String(localized: "Disconnected")))

    }

    func clear() {
        events.removeAll()
    }

    // MARK: - Event Handling

    func handleEvent(_ event: SseEvent) {
        switch event {
        case .connected:
            isConnecting = false
            isConnected = true
            events.append(.system(String(localized: "Connected")))


        case .eventReceived(let eventType, let data, let id):
            if let id { lastEventId = id }
            let entry = SseEventEntry(eventType: eventType, data: data, eventId: id)
            events.append(entry)
            unreadCount += 1


        case .retryChanged(let retryMs):
            events.append(.system(String(localized: "Retry interval changed to \(retryMs)ms")))

        case .disconnected(let reason):
            isConnected = false
            isConnecting = false
            client = nil
            events.append(.system(String(localized: "Disconnected: \(reason)")))


        case .error(let errorMsg):
            isConnected = false
            isConnecting = false
            client = nil
            error = RequestError.from(message: errorMsg, kind: .sseError)
            events.append(.system(String(localized: "Error: \(errorMsg)")))

        }
    }
}
