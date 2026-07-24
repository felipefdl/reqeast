//
//  EnvironmentEntity.swift
//  Reqeast
//

import AppIntents

struct EnvironmentEntity: AppEntity {
    static var defaultQuery = EnvironmentEntityQuery()
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Environment"

    var id: UUID
    var projectId: UUID
    var name: String
    var projectName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(projectName)")
    }

    init(id: UUID, projectId: UUID, name: String, projectName: String = "") {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.projectName = projectName
    }

    init(from environment: ApiEnvironment, projectName: String = "") {
        self.id = environment.id
        self.projectId = environment.projectId
        self.name = environment.name
        self.projectName = projectName
    }
}
