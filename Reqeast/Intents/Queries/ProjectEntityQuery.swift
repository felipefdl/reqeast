//
//  ProjectEntityQuery.swift
//  Reqeast
//

import AppIntents

struct ProjectEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async -> [ProjectEntity] {
        let projects = await MainActor.run { ProjectStore.shared.projects }
        return projects
            .filter { identifiers.contains($0.id) && $0.deletedAt == nil }
            .map { ProjectEntity(from: $0) }
    }

    func suggestedEntities() async -> [ProjectEntity] {
        let projects = await MainActor.run { ProjectStore.shared.projects }
        return projects
            .filter { $0.deletedAt == nil }
            .map { ProjectEntity(from: $0) }
    }
}
