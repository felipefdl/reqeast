//
//  SpecImportTypes.swift
//  Reqeast
//

import Foundation

struct SpecImportEnvironmentBinding: Equatable, Identifiable {
    /// Stable key for merging user edits across re-preview (absolute source path).
    var sourceKey: String
    var sourceFileName: String
    var specTitle: String
    var variableName: String
    var baseURL: String

    var id: String { sourceKey }
}

struct SpecImportBatchPreview: Equatable {
    var items: [SpecImportPreview]
    var sourceFolderName: String

    var specCount: Int { items.count }

    var totalOperationCount: Int {
        items.reduce(0) { $0 + $1.operationCount }
    }

    var allWarnings: [SpecWarning] {
        items.flatMap(\.warnings)
    }
}

enum SpecImportPhase: Equatable {
    case sourcePick
    case parsing
    case preview(SpecImportPreview)
    case batchPreview(SpecImportBatchPreview)
    case importing(SpecImportPreview)
    case importingBatch(SpecImportBatchPreview)
    case error(SpecImportError)
}

enum SpecImportTarget: String, CaseIterable, Hashable, Identifiable {
    case newProject
    case existingProject

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .newProject: String(localized: "New project")
        case .existingProject: String(localized: "Existing project")
        }
    }
}

enum SpecImportSourceTab: String, CaseIterable, Identifiable {
    case file
    case url
    case paste

    var id: String { rawValue }

    var label: String {
        switch self {
        case .file: String(localized: "File")
        case .url: String(localized: "URL")
        case .paste: String(localized: "Paste")
        }
    }

    var systemImage: String {
        switch self {
        case .file: "doc"
        case .url: "link"
        case .paste: "doc.on.clipboard"
        }
    }
}