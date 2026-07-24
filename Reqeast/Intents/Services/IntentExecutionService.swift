//
//  IntentExecutionService.swift
//  Reqeast
//

import Foundation

enum IntentExecutionError: Error, CustomLocalizedStringResourceConvertible {
    case requestNotFound
    case environmentNotFound
    case executionFailed(String)
    case timeout
    case noResponse(String)
    case messageRequired
    case noRequestsInProject
    case unresolvedVariables([String])

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .requestNotFound:
            "Request not found. It may have been deleted."
        case .environmentNotFound:
            "Environment not found. It may have been deleted."
        case .executionFailed(let detail):
            "Execution failed: \(detail)"
        case .timeout:
            "Request timed out."
        case .noResponse(let reason):
            "No response received: \(reason)"
        case .messageRequired:
            "A message is required for this protocol."
        case .noRequestsInProject:
            "The selected project has no requests."
        case .unresolvedVariables(let names):
            "Unresolved template variables: \(names.map { "{{\($0)}}" }.joined(separator: ", "))"
        }
    }
}

enum IntentExecutionService {}

func intentWithTimeout<T: Sendable>(
    seconds: Int,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds + 5))
            throw IntentExecutionError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
