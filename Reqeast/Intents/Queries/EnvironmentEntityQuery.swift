//
//  EnvironmentEntityQuery.swift
//  Reqeast
//

import AppIntents

struct EnvironmentEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async -> [EnvironmentEntity] {
        let (environments, projectNames) = await MainActor.run {
            let envs = ProjectStore.shared.environments.filter { $0.deletedAt == nil }
            let names = envProjectNameLookup(from: ProjectStore.shared.projects.filter { $0.deletedAt == nil })
            return (envs, names)
        }
        return environments
            .filter { identifiers.contains($0.id) }
            .map { EnvironmentEntity(from: $0, projectName: projectNames[$0.projectId] ?? "") }
    }

    func suggestedEntities() async -> [EnvironmentEntity] {
        let (environments, projectNames) = await MainActor.run {
            let envs = ProjectStore.shared.environments.filter { $0.deletedAt == nil }
            let names = envProjectNameLookup(from: ProjectStore.shared.projects.filter { $0.deletedAt == nil })
            return (envs, names)
        }
        return environments
            .sorted { (projectNames[$0.projectId] ?? "") < (projectNames[$1.projectId] ?? "") }
            .map { EnvironmentEntity(from: $0, projectName: projectNames[$0.projectId] ?? "") }
    }
}

private func envProjectNameLookup(from projects: [Project]) -> [UUID: String] {
    Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
}
