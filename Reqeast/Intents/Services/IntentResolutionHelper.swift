//
//  IntentResolutionHelper.swift
//  Reqeast
//

import AppIntents
import Foundation

enum IntentResolutionHelper {

    static func validateRequestData(_ request: Request) throws {
        switch request.type {
        case .http:
            guard request.httpData != nil else {
                throw IntentExecutionError.executionFailed("Missing HTTP configuration")
            }
        case .tcp:
            guard request.tcpData != nil else {
                throw IntentExecutionError.executionFailed("Missing TCP configuration")
            }
        case .udp:
            guard request.udpData != nil else {
                throw IntentExecutionError.executionFailed("Missing UDP configuration")
            }
        case .webSocket:
            guard request.webSocketData != nil else {
                throw IntentExecutionError.executionFailed("Missing WebSocket configuration")
            }
        case .sse:
            guard request.sseData != nil else {
                throw IntentExecutionError.executionFailed("Missing SSE configuration")
            }
        case .grpc:
            guard request.grpcData != nil else {
                throw IntentExecutionError.executionFailed("Missing gRPC configuration")
            }
        }
    }

    static func resolveRequest(
        projectId: UUID,
        selectedEntity: RequestEntity?,
        typeFilter: RequestType,
        disambiguate: ([RequestEntity]) async throws -> RequestEntity
    ) async throws -> Request {
        let projectRequests = await MainActor.run {
            ProjectStore.shared.requests(for: projectId).filter { $0.type == typeFilter }
        }

        guard !projectRequests.isEmpty else {
            throw IntentExecutionError.noRequestsInProject
        }

        if let selectedEntity {
            if let resolved = projectRequests.first(where: { $0.id == selectedEntity.id }) {
                return resolved
            }
        }

        let entities = projectRequests.map { RequestEntity(from: $0) }
        let chosen = try await disambiguate(entities)

        guard let resolved = projectRequests.first(where: { $0.id == chosen.id }) else {
            throw IntentExecutionError.requestNotFound
        }
        return resolved
    }

    static func resolveEnvironment(
        projectId: UUID,
        selectedEntity: EnvironmentEntity?,
        disambiguate: ([EnvironmentEntity]) async throws -> EnvironmentEntity
    ) async throws -> ApiEnvironment? {
        guard let envEntity = selectedEntity else { return nil }

        let projectEnvironments = await MainActor.run {
            ProjectStore.shared.environments(for: projectId)
        }

        if let found = projectEnvironments.first(where: { $0.id == envEntity.id }) {
            return found
        }

        guard !projectEnvironments.isEmpty else { return nil }

        let entities = projectEnvironments.map { EnvironmentEntity(from: $0) }
        let chosen = try await disambiguate(entities)
        return projectEnvironments.first { $0.id == chosen.id }
    }

    static func resolveVariableOverrides(
        for request: Request,
        environment: ApiEnvironment?,
        overridesInput: String?,
        requestOverridesInput: (_ unresolvedVariables: [String]) async throws -> String
    ) async throws -> ApiEnvironment? {
        let unresolved = TemplateExtractor.unresolvedVariables(in: request, environment: environment)
        guard !unresolved.isEmpty else { return environment }

        var parsed = parseVariableOverrides(overridesInput)
        let stillUnresolved = unresolved.filter { parsed[$0] == nil }

        if !stillUnresolved.isEmpty && overridesInput == nil {
            let input = try await requestOverridesInput(stillUnresolved)
            parsed = parseVariableOverrides(input)
        }

        let finalUnresolved = unresolved.filter { parsed[$0] == nil }
        if !finalUnresolved.isEmpty {
            throw IntentExecutionError.unresolvedVariables(finalUnresolved)
        }

        let overrideVars = parsed.map { EnvironmentVariable(key: $0.key, value: $0.value) }
        var merged = environment ?? ApiEnvironment(projectId: request.projectId, name: "Shortcut Overrides")
        merged.variables.append(contentsOf: overrideVars)
        return merged
    }

    static func resolveMessage(
        message: String?,
        requestInput: () async throws -> String
    ) async throws -> String {
        if let message, !message.isEmpty { return message }
        return try await requestInput()
    }

    static func parseVariableOverrides(_ input: String?) -> [String: String] {
        guard let input, !input.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for line in input.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eqIndex].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            result[key] = value
        }
        return result
    }
}
