//
//  ApiEnvironment.swift
//  Reqeast
//

import Foundation

struct ApiEnvironment: Codable, Identifiable, Hashable {
    var id: UUID
    var projectId: UUID
    var name: String
    var variables: [EnvironmentVariable]
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var schemaVersion: Int = CloudSyncableSchema.currentVersion

    init(
        id: UUID = UUID(),
        projectId: UUID,
        name: String,
        variables: [EnvironmentVariable] = [],
        isActive: Bool = false
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.variables = variables
        self.isActive = isActive
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectId = try container.decode(UUID.self, forKey: .projectId)
        name = try container.decode(String.self, forKey: .name)
        variables = try container.decode([EnvironmentVariable].self, forKey: .variables)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        schemaVersion = try CloudSyncableSchema.decodeVersion(from: container, forKey: .schemaVersion)
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, name, variables, isActive, createdAt, updatedAt, deletedAt, schemaVersion
    }
}

struct EnvironmentVariable: Codable, Identifiable, Hashable {
    var id: UUID
    var key: String
    var value: String
    var isSecret: Bool
    var enabled: Bool

    init(
        id: UUID = UUID(),
        key: String = "",
        value: String = "",
        isSecret: Bool = false,
        enabled: Bool = true
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isSecret = isSecret
        self.enabled = enabled
    }

    var isEmpty: Bool {
        key.isEmpty && value.isEmpty
    }
}
