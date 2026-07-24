//
//  GrpcRequestView+Streaming.swift
//  Reqeast
//

import SwiftUI

extension GrpcRequestFullView {
    func buildGrpcConfig(data: GrpcRequestData, rpcKind: GrpcRpcKind) -> GrpcConfig {
        let env = store.activeEnvironment(for: request.projectId)
        let authority = EnvironmentVariableService.substitute(data.authority, environment: env)
        let service = EnvironmentVariableService.substitute(data.service, environment: env)
        let method = EnvironmentVariableService.substitute(data.method, environment: env)
        let metadata = data.metadata
            .filter { $0.enabled && !$0.key.isEmpty }
            .map {
                KeyValuePair(
                    key: $0.key,
                    value: EnvironmentVariableService.substitute($0.value, environment: env),
                    enabled: true
                )
            }
        return GrpcConfig(
            authority: authority,
            useTls: data.useTls,
            allowInsecureTls: data.allowInsecureTls,
            metadata: metadata,
            service: service,
            method: method,
            rpcKind: rpcKind,
            deadlineMs: UInt32(clamping: data.deadlineMs),
            timeoutSecs: UInt32(clamping: data.timeoutSeconds)
        )
    }

    func connectStream() {
        guard canConnectStream, let descriptorBytes = cachedDescriptorBytes else { return }
        let data = readData()
        let config = buildGrpcConfig(data: data, rpcKind: resolvedRpcKind(for: data))
        let payload = substitutedRequestPayload()

        Task {
            if let validationError = await validateBodyBeforeSend() {
                bodyValidationError = validationError
                return
            }
            bodyValidationError = nil
            sessionStore.startStream(
                config: config,
                descriptorBytes: descriptorBytes,
                requestBody: payload.body,
                bodyIsHex: payload.isHex
            )
        }
    }

    func sendStreamMessage() {
        let data = readData()
        let rpcKind = resolvedRpcKind(for: data)
        let payload = substitutedRequestPayload()

        Task {
            if let validationError = await validateBodyBeforeSend() {
                bodyValidationError = validationError
                return
            }
            bodyValidationError = nil

            switch rpcKind {
            case .unary:
                return
            case .serverStreaming:
                guard canSendStream, let descriptorBytes = cachedDescriptorBytes else { return }
                let config = buildGrpcConfig(data: data, rpcKind: rpcKind)
                sessionStore.startStream(
                    config: config,
                    descriptorBytes: descriptorBytes,
                    requestBody: payload.body,
                    bodyIsHex: payload.isHex
                )
            case .clientStreaming, .bidirectional:
                guard sessionStore.isConnected else { return }
                sessionStore.sendMessage(payload.body, bodyIsHex: payload.isHex)
            }
        }
    }

    func halfCloseStream() {
        sessionStore.halfClose()
    }

    func cancelStream() {
        sessionStore.cancel()
    }
}