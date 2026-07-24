//
//  ExportDocument.swift
//  Reqeast
//

import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let reqeastExport = UTType(exportedAs: "app.reqeast.project-export", conformingTo: .json)
}

struct ExportDocument: Codable {
    static let currentVersion = 1

    let version: Int
    let exportedAt: Date
    let appVersion: String
    let project: Project
    let requests: [ExportedRequest]
    let requestFolders: [RequestFolder]
    let environments: [ExportedEnvironment]
}

struct ExportedRequest: Codable {
    let request: Request
    let credentials: RequestCredentials?
}

struct ExportedEnvironment: Codable {
    let environment: ApiEnvironment
    let includesSecrets: Bool
}

struct ImportResult: Identifiable {
    let id = UUID()
    let document: ExportDocument
    let fileName: String
}

// MARK: - Bundle (Multi-Project)

struct ExportBundle: Codable {
    static let currentVersion = 1

    let version: Int
    let exportedAt: Date
    let appVersion: String
    let projects: [ExportDocument]
    let projectFolders: [ProjectFolder]

    init(
        version: Int, exportedAt: Date, appVersion: String,
        projects: [ExportDocument], projectFolders: [ProjectFolder]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.projects = projects
        self.projectFolders = projectFolders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        projects = try container.decode([ExportDocument].self, forKey: .projects)
        projectFolders = try container.decodeIfPresent([ProjectFolder].self, forKey: .projectFolders) ?? []
    }
}

struct ImportBundleResult: Identifiable {
    let id = UUID()
    let bundle: ExportBundle
    let fileName: String
}
