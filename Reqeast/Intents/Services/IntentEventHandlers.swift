//
//  IntentEventHandlers.swift
//  Reqeast
//

import Foundation

// MARK: - TCP

final class IntentTcpEventHandler: TcpEventHandler, @unchecked Sendable {
    private let continuation: CheckedContinuation<String, Error>
    private let client: TcpClient
    private let messageToSend: Data
    private let lock = NSLock()
    private var resumed = false

    init(continuation: CheckedContinuation<String, Error>, client: TcpClient, messageToSend: Data) {
        self.continuation = continuation
        self.client = client
        self.messageToSend = messageToSend
    }

    func onEvent(event: TcpEvent) {
        switch event {
        case .connected:
            do {
                try client.send(data: messageToSend)
            } catch {
                resume(with: .failure(IntentExecutionError.executionFailed(error.localizedDescription)))
            }

        case .dataReceived(let data):
            let text = String(data: Data(data), encoding: .utf8) ?? Data(data).base64EncodedString()
            try? client.disconnect()
            resume(with: .success(text))

        case .disconnected(let reason):
            resume(with: .failure(IntentExecutionError.noResponse(reason)))

        case .error(let error):
            resume(with: .failure(IntentExecutionError.executionFailed(error)))
        }
    }

    private func resume(with result: Result<String, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(with: result)
    }
}

// MARK: - UDP

final class IntentUdpEventHandler: UdpEventHandler, @unchecked Sendable {
    private let continuation: CheckedContinuation<String, Error>
    private let client: UdpClient
    private let lock = NSLock()
    private var resumed = false

    init(continuation: CheckedContinuation<String, Error>, client: UdpClient) {
        self.continuation = continuation
        self.client = client
    }

    func onEvent(event: UdpEvent) {
        switch event {
        case .dataReceived(let data, _):
            let text = String(data: Data(data), encoding: .utf8) ?? Data(data).base64EncodedString()
            try? client.stop()
            resume(with: .success(text))

        case .error(let error):
            resume(with: .failure(IntentExecutionError.executionFailed(error)))
        }
    }

    private func resume(with result: Result<String, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(with: result)
    }
}

// MARK: - WebSocket

final class IntentWsEventHandler: WsEventHandler, @unchecked Sendable {
    private let continuation: CheckedContinuation<String, Error>
    private let client: WsClient
    private let messageToSend: String
    private let lock = NSLock()
    private var resumed = false

    init(continuation: CheckedContinuation<String, Error>, client: WsClient, messageToSend: String) {
        self.continuation = continuation
        self.client = client
        self.messageToSend = messageToSend
    }

    func onEvent(event: WsEvent) {
        switch event {
        case .connected:
            do {
                try client.sendText(text: messageToSend)
            } catch {
                resume(with: .failure(IntentExecutionError.executionFailed(error.localizedDescription)))
            }

        case .textReceived(let text):
            try? client.disconnect()
            resume(with: .success(text))

        case .binaryReceived(let data):
            let text = String(data: Data(data), encoding: .utf8) ?? Data(data).base64EncodedString()
            try? client.disconnect()
            resume(with: .success(text))

        case .disconnected(_, let reason):
            resume(with: .failure(IntentExecutionError.noResponse(reason)))

        case .error(let error):
            resume(with: .failure(IntentExecutionError.executionFailed(error)))

        case .pongReceived:
            break
        }
    }

    private func resume(with result: Result<String, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(with: result)
    }
}

// MARK: - SSE

final class IntentSseEventHandler: SseEventHandler, @unchecked Sendable {
    private let continuation: CheckedContinuation<String, Error>
    private let client: SseClient
    private let lock = NSLock()
    private var resumed = false

    init(continuation: CheckedContinuation<String, Error>, client: SseClient) {
        self.continuation = continuation
        self.client = client
    }

    func onEvent(event: SseEvent) {
        switch event {
        case .connected:
            break

        case .eventReceived(_, let data, _):
            try? client.disconnect()
            resume(with: .success(data))

        case .retryChanged:
            break

        case .disconnected(let reason):
            resume(with: .failure(IntentExecutionError.noResponse(reason)))

        case .error(let error):
            resume(with: .failure(IntentExecutionError.executionFailed(error)))
        }
    }

    private func resume(with result: Result<String, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(with: result)
    }
}
