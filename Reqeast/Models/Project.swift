//
//  Project.swift
//  Reqeast
//

import Foundation
import SwiftUI

struct Project: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var emoji: String?
    var iconURL: String?
    var color: FolderColor
    var folderId: UUID?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var specLink: SpecLink?
    var schemaVersion: Int = CloudSyncableSchema.currentVersion

    /// Supported image extensions for icon URLs.
    static let allowedIconExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "ico"]

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String? = nil,
        iconURL: String? = nil,
        color: FolderColor = .gray,
        folderId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.iconURL = iconURL
        self.color = color
        self.folderId = folderId
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL)
        color = try container.decodeIfPresent(FolderColor.self, forKey: .color) ?? .gray
        folderId = try container.decodeIfPresent(UUID.self, forKey: .folderId)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        specLink = try container.decodeIfPresent(SpecLink.self, forKey: .specLink)
        schemaVersion = try CloudSyncableSchema.decodeVersion(from: container, forKey: .schemaVersion)
    }
}

struct ProjectFolder: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var color: FolderColor
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var schemaVersion: Int = CloudSyncableSchema.currentVersion

    init(id: UUID = UUID(), name: String, color: FolderColor = .gray) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeIfPresent(FolderColor.self, forKey: .color) ?? .gray
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        schemaVersion = try CloudSyncableSchema.decodeVersion(from: container, forKey: .schemaVersion)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color, createdAt, updatedAt, deletedAt, schemaVersion
    }
}

enum FolderColor: String, Codable, CaseIterable, Hashable {
    case gray
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink

    var color: Color {
        switch self {
        case .gray:   return .gray
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .blue:   return .blue
        case .purple: return .purple
        case .pink:   return .pink
        }
    }

    var localizedName: String {
        switch self {
        case .gray:   return String(localized: "Gray")
        case .red:    return String(localized: "Red")
        case .orange: return String(localized: "Orange")
        case .yellow: return String(localized: "Yellow")
        case .green:  return String(localized: "Green")
        case .blue:   return String(localized: "Blue")
        case .purple: return String(localized: "Purple")
        case .pink:   return String(localized: "Pink")
        }
    }
}
