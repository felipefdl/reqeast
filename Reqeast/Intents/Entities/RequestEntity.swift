//
//  RequestEntity.swift
//  Reqeast
//

import AppIntents

struct RequestEntity: AppEntity {
    static var defaultQuery = RequestEntityQuery()
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Request"

    var id: UUID
    var projectId: UUID
    var name: String
    var typeName: String
    var projectName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(projectName) \u{2022} \(typeName)")
    }

    init(id: UUID, projectId: UUID, name: String, typeName: String, projectName: String = "") {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.typeName = typeName
        self.projectName = projectName
    }

    init(from request: Request, projectName: String = "") {
        self.id = request.id
        self.projectId = request.projectId
        self.name = request.name
        self.typeName = request.type.localizedName
        self.projectName = projectName
    }
}
