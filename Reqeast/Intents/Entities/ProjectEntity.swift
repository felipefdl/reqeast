//
//  ProjectEntity.swift
//  Reqeast
//

import AppIntents

struct ProjectEntity: AppEntity {
    static var defaultQuery = ProjectEntityQuery()
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Project"

    var id: UUID
    var name: String
    var emoji: String?

    var displayRepresentation: DisplayRepresentation {
        let title = if let emoji { "\(emoji) \(name)" } else { name }
        return DisplayRepresentation(title: "\(title)")
    }

    init(id: UUID, name: String, emoji: String?) {
        self.id = id
        self.name = name
        self.emoji = emoji
    }

    init(from project: Project) {
        self.id = project.id
        self.name = project.name
        self.emoji = project.emoji
    }
}
