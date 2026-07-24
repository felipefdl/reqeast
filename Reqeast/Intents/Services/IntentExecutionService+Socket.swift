//
//  IntentExecutionService+Socket.swift
//  Reqeast
//

import Foundation

// MARK: - TCP

extension IntentExecutionService {

    static func executeTcp(
        request: Request,
        environment: ApiEnvironment?,
        message: String?,
        timeout: Int
    ) async throws -> String {
        guard let data = request.tcpData else {
            throw IntentExecutionError.executionFailed("Missing TCP configuration")
        }
        guard let message, !message.isEmpty else {
            throw IntentExecutionError.messageRequired
        }

        let sub: (String) -> String = { EnvironmentVariableService.substitute($0, environment: environment) }
        let host = sub(data.host)
        let messageData = Data(message.utf8) + data.lineEnding.bytes
        let client = try TcpClient()
        let config = TcpConfig(
            host: host,
            port: UInt16(data.port),
            useTls: data.useTls,
            allowInsecureTls: data.allowInsecureTls,
            timeoutSecs: UInt32(timeout)
        )

        return try await intentWithTimeout(seconds: timeout) {
            try await withCheckedThrowingContinuation { continuation in
                let handler = IntentTcpEventHandler(
                    continuation: continuation,
                    client: client,
                    messageToSend: messageData
                )
                do {
                    try client.connect(config: config, handler: handler)
                } catch {
                    continuation.resume(throwing: IntentExecutionError.executionFailed(error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - UDP

extension IntentExecutionService {

    static func executeUdp(
        request: Request,
        environment: ApiEnvironment?,
        message: String?,
        timeout: Int
    ) async throws -> String {
        guard let data = request.udpData else {
            throw IntentExecutionError.executionFailed("Missing UDP configuration")
        }
        guard let message, !message.isEmpty else {
            throw IntentExecutionError.messageRequired
        }

        let sub: (String) -> String = { EnvironmentVariableService.substitute($0, environment: environment) }
        let host = sub(data.host)
        let messageData = Data(message.utf8) + data.lineEnding.bytes
        let client = try UdpClient()
        let config = UdpConfig(
            host: host,
            port: UInt16(data.port),
            bindPort: data.bindPort.map { UInt16($0) },
            timeoutSecs: UInt32(timeout)
        )

        return try await intentWithTimeout(seconds: timeout) {
            try await withCheckedThrowingContinuation { continuation in
                let handler = IntentUdpEventHandler(continuation: continuation, client: client)
                do {
                    try client.start(config: config, handler: handler)
                    try client.send(data: messageData)
                } catch {
                    continuation.resume(throwing: IntentExecutionError.executionFailed(error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - WebSocket

extension IntentExecutionService {

    static func executeWebSocket(
        request: Request,
        environment: ApiEnvironment?,
        message: String?,
        timeout: Int
    ) async throws -> String {
        guard let data = request.webSocketData else {
            throw IntentExecutionError.executionFailed("Missing WebSocket configuration")
        }
        guard let message, !message.isEmpty else {
            throw IntentExecutionError.messageRequired
        }

        let sub: (String) -> String = { EnvironmentVariableService.substitute($0, environment: environment) }
        let url = sub(data.url)
        let headers = data.headers.filter { $0.enabled && !$0.key.isEmpty }
            .map { KeyValuePair(key: sub($0.key), value: sub($0.value), enabled: true) }
        let subprotocols = data.subprotocols.split(separator: ",")
            .map { String($0.trimmingCharacters(in: .whitespaces)) }
        let client = try WsClient()
        let config = WsConfig(
            url: url,
            headers: headers,
            subprotocols: subprotocols,
            timeoutSecs: UInt32(timeout),
            allowInsecureTls: data.allowInsecureTls
        )

        return try await intentWithTimeout(seconds: timeout) {
            try await withCheckedThrowingContinuation { continuation in
                let handler = IntentWsEventHandler(
                    continuation: continuation,
                    client: client,
                    messageToSend: message
                )
                do {
                    try client.connect(config: config, handler: handler)
                } catch {
                    continuation.resume(throwing: IntentExecutionError.executionFailed(error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - SSE

extension IntentExecutionService {

    static func executeSse(request: Request, environment: ApiEnvironment?, timeout: Int) async throws -> String {
        guard let data = request.sseData else {
            throw IntentExecutionError.executionFailed("Missing SSE configuration")
        }

        let sub: (String) -> String = { EnvironmentVariableService.substitute($0, environment: environment) }
        let url = sub(data.url)
        let headers = data.headers.filter { $0.enabled && !$0.key.isEmpty }
            .map { KeyValuePair(key: sub($0.key), value: sub($0.value), enabled: true) }
        let client = try SseClient()
        let config = SseConfig(
            url: url,
            headers: headers,
            timeoutSecs: UInt32(timeout),
            sslVerify: data.sslVerify,
            lastEventId: nil
        )

        return try await intentWithTimeout(seconds: timeout) {
            try await withCheckedThrowingContinuation { continuation in
                let handler = IntentSseEventHandler(continuation: continuation, client: client)
                do {
                    try client.connect(config: config, handler: handler)
                } catch {
                    continuation.resume(throwing: IntentExecutionError.executionFailed(error.localizedDescription))
                }
            }
        }
    }
}
