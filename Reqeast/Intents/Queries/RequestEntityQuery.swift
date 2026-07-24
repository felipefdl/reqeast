//
//  RequestEntityQuery.swift
//  Reqeast
//

import AppIntents

struct RequestEntityQuery: EntityQuery {
    @IntentParameterDependency<SendHttpRequestIntent>(\.$project)
    var httpIntent

    @IntentParameterDependency<SendTcpMessageIntent>(\.$project)
    var tcpIntent

    @IntentParameterDependency<SendUdpMessageIntent>(\.$project)
    var udpIntent

    @IntentParameterDependency<SendWebSocketMessageIntent>(\.$project)
    var wsIntent

    @IntentParameterDependency<SendSseRequestIntent>(\.$project)
    var sseIntent

    @IntentParameterDependency<SendGrpcRequestIntent>(\.$project)
    var grpcIntent

    func entities(for identifiers: [UUID]) async -> [RequestEntity] {
        let (requests, projectNames) = await MainActor.run {
            let reqs = ProjectStore.shared.requests.filter { $0.deletedAt == nil }
            let names = projectNameLookup(from: ProjectStore.shared.projects.filter { $0.deletedAt == nil })
            return (reqs, names)
        }
        return requests
            .filter { identifiers.contains($0.id) }
            .map { RequestEntity(from: $0, projectName: projectNames[$0.projectId] ?? "") }
    }

    func suggestedEntities() async -> [RequestEntity] {
        let (requests, projectNames) = await MainActor.run {
            let reqs = ProjectStore.shared.requests.filter { $0.deletedAt == nil }
            let names = projectNameLookup(from: ProjectStore.shared.projects.filter { $0.deletedAt == nil })
            return (reqs, names)
        }

        let (projectId, typeFilter) = resolveContext()

        var filtered = requests
        if let projectId {
            filtered = filtered.filter { $0.projectId == projectId }
        }
        if let typeFilter {
            filtered = filtered.filter { $0.type == typeFilter }
        }
        if projectId == nil {
            filtered = filtered.sorted {
                (projectNames[$0.projectId] ?? "") < (projectNames[$1.projectId] ?? "")
            }
        }

        return filtered.map { RequestEntity(from: $0, projectName: projectNames[$0.projectId] ?? "") }
    }

    private func resolveContext() -> (UUID?, RequestType?) {
        if let intent = httpIntent { return (intent.project.id, .http) }
        if let intent = tcpIntent { return (intent.project.id, .tcp) }
        if let intent = udpIntent { return (intent.project.id, .udp) }
        if let intent = wsIntent { return (intent.project.id, .webSocket) }
        if let intent = sseIntent { return (intent.project.id, .sse) }
        if let intent = grpcIntent { return (intent.project.id, .grpc) }
        return (nil, nil)
    }
}

private func projectNameLookup(from projects: [Project]) -> [UUID: String] {
    Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
}
