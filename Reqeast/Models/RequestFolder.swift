//
//  RequestFolder.swift
//  Reqeast
//

import Foundation

struct RequestFolder: Codable, Identifiable, Hashable {
    var id: UUID
    var projectId: UUID
    var name: String
    var color: FolderColor
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var schemaVersion: Int = CloudSyncableSchema.currentVersion

    init(id: UUID = UUID(), projectId: UUID, name: String, color: FolderColor = .blue) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.color = color
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectId = try container.decode(UUID.self, forKey: .projectId)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeIfPresent(FolderColor.self, forKey: .color) ?? .blue
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        schemaVersion = try CloudSyncableSchema.decodeVersion(from: container, forKey: .schemaVersion)
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, name, color, createdAt, updatedAt, deletedAt, schemaVersion
    }
}
