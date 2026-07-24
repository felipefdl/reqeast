//
//  IntentExecutionService+Grpc.swift
//  Reqeast
//

import Foundation

extension IntentExecutionService {

    static func executeGrpc(request: Request, environment: ApiEnvironment?, timeout: Int) async throws -> String {
        guard let data = request.grpcData else {
            throw IntentExecutionError.executionFailed("Missing gRPC configuration")
        }

        guard data.rpcKind == .unary else {
            throw IntentExecutionError.executionFailed("Shortcuts supports unary gRPC requests only")
        }

        let descriptorBytes = try await MainActor.run {
            try loadProtoDescriptorBytes(projectId: request.projectId, data: data)
        }

        let sub: (String) -> String = { EnvironmentVariableService.substitute($0, environment: environment) }
        let authority = sub(data.authority)
        let service = sub(data.service)
        let method = sub(data.method)
        let metadata = data.metadata
            .filter { $0.enabled && !$0.key.isEmpty }
            .map {
                KeyValuePair(
                    key: sub($0.key),
                    value: sub($0.value),
                    enabled: true
                )
            }
        let requestBody: String
        let bodyIsHex: Bool
        switch data.bodyMode {
        case .json:
            requestBody = sub(data.requestBodyJSON)
            bodyIsHex = false
        case .hex:
            requestBody = sub(data.requestBodyHex)
            bodyIsHex = true
        }

        let config = GrpcConfig(
            authority: authority,
            useTls: data.useTls,
            allowInsecureTls: data.allowInsecureTls,
            metadata: metadata,
            service: service,
            method: method,
            rpcKind: .unary,
            deadlineMs: UInt32(clamping: data.deadlineMs),
            timeoutSecs: UInt32(clamping: timeout)
        )

        return try await intentWithTimeout(seconds: timeout) {
            let response = try await GrpcService.invokeUnary(
                config: config,
                descriptorBytes: descriptorBytes,
                requestBody: requestBody,
                bodyIsHex: bodyIsHex
            )
            return response.responseJson
        }
    }

    @MainActor
    private static func loadProtoDescriptorBytes(projectId: UUID, data: GrpcRequestData) throws -> Data {
        guard let protoBundleId = data.protoBundleId else {
            throw IntentExecutionError.executionFailed("No proto bundle selected for this gRPC request")
        }

        guard let bundle = ProjectStore.shared.protoBundle(id: protoBundleId) else {
            throw IntentExecutionError.executionFailed("Proto bundle not found for this gRPC request")
        }

        guard bundle.projectId == projectId else {
            throw IntentExecutionError.executionFailed("Proto bundle does not belong to this project")
        }

        guard ProjectStore.shared.isGrpcProtoReady(protoBundleId: protoBundleId) else {
            throw IntentExecutionError.executionFailed(
                "Proto descriptors are unavailable on this device. Download the bundle from iCloud before running this shortcut."
            )
        }

        guard let descriptorBytes = ProtoBundle.loadDescriptorBytes(projectId: projectId, bundleId: protoBundleId),
              !descriptorBytes.isEmpty else {
            throw IntentExecutionError.executionFailed("Proto descriptor bytes not found on disk")
        }

        return descriptorBytes
    }
}