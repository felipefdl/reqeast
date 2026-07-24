//
//  SpecExportTypes.swift
//  Reqeast
//

import Foundation

enum SpecExportKind: Hashable {
    case openapi
    case postman
}

enum SpecExportOpenApiFormat: String, CaseIterable, Hashable {
    case yaml
    case json

    var localizedName: String {
        switch self {
        case .yaml: String(localized: "YAML")
        case .json: String(localized: "JSON")
        }
    }

    var exportFormat: ExportFormat {
        switch self {
        case .yaml: .yaml
        case .json: .json
        }
    }
}

struct SpecExportOptions: Equatable, Hashable {
    var openApiFormat: SpecExportOpenApiFormat = .yaml
    var includeEnvironments: Bool = true
    var includeDeprecatedAndStale: Bool = true

    static let `default` = SpecExportOptions()
}

struct SpecExportTarget: Identifiable, Hashable {
    let id = UUID()
    let project: Project
    let kind: SpecExportKind
}

/// Review sheet payload for linked projects (inverted Rule A).
struct SpecExportReviewContext: Identifiable, Equatable {
    let id = UUID()
    let diff: SpecSyncDiff
    let specProject: NormalizedProject
    let kind: SpecExportKind
    let options: SpecExportOptions
}

/// Per-operation export review choices. Defaults favor local edits (inverted Rule A).
struct SpecExportSelections: Equatable {
    /// Added operations (only in project) to include in the export file.
    var includeProjectOnlyPrimaryKeys: Set<String> = []
    /// Removed operations (only in on-disk spec) to pull into the export file.
    var includeSpecOnlyPrimaryKeys: Set<String> = []
    /// Modified / identity-changed rows that should keep the local version in export.
    var useLocalVersionRequestIDs: Set<String> = []

    var hasExportableSelection: Bool {
        !includeProjectOnlyPrimaryKeys.isEmpty
            || !includeSpecOnlyPrimaryKeys.isEmpty
            || !useLocalVersionRequestIDs.isEmpty
    }
}

enum SpecExportReviewSegment: String, CaseIterable, Identifiable {
    case projectOnly
    case specOnly
    case changed
    case conflicts

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .projectOnly: String(localized: "Only in project")
        case .specOnly: String(localized: "Only in spec")
        case .changed: String(localized: "Changed")
        case .conflicts: String(localized: "Conflicts")
        }
    }
}

enum SpecExportServiceError: LocalizedError, Equatable {
    case noOperations
    case exportFailed(String)
    case clipboardEncodingFailed

    var errorDescription: String? {
        switch self {
        case .noOperations:
            String(localized: "This project has no HTTP requests to export.")
        case .exportFailed(let message):
            message
        case .clipboardEncodingFailed:
            String(localized: "Could not copy export data to the clipboard.")
        }
    }
}