//
//  SpecImportAccessibility.swift
//  Reqeast
//

import Foundation

enum SpecImportAccessibility {
    static let sourcePicker = "spec-import-source-picker"

    static func sourceTab(_ tab: SpecImportSourceTab) -> String {
        "spec-import-source-tab-\(tab.rawValue)"
    }
    static let chooseFileButton = "spec-import-choose-file"
    static let chooseFolderButton = "spec-import-choose-folder"
    static let urlField = "spec-import-url-field"
    static let pasteEditor = "spec-import-paste-editor"
    static let pasteByteCount = "spec-import-paste-byte-count"
    static let fetchButton = "spec-import-fetch-button"
    static let continueButton = "spec-import-continue-button"
    static let detectedFormat = "spec-import-detected-format"
    static let importTarget = "spec-import-import-target"

    static func importTargetOption(_ target: SpecImportTarget) -> String {
        "spec-import-import-target-\(target.rawValue)"
    }
    static let importTargetNote = "spec-import-import-target-note"
    static let existingProjectPicker = "spec-import-existing-project-picker"

    static func existingProjectOption(_ name: String) -> String {
        "spec-import-existing-project-\(name)"
    }
    static let projectNameField = "spec-import-project-name"
    static let operationCount = "spec-import-operation-count"
    static let folderCount = "spec-import-folder-count"
    static let advancedOptions = "spec-import-advanced-options"
    static let linkToSpec = "spec-import-link-to-spec"
    static let urlSnapshotDisclaimer = "spec-import-url-snapshot-disclaimer"
    static let urlLinkedDisclaimer = "spec-import-url-linked-disclaimer"
    static let preferredBodyContentType = "spec-import-preferred-body-content-type"
    static let enableSchemaSynthesis = "spec-import-enable-schema-synthesis"
    static let importHarCredentialsAsPlaceholders = "spec-import-import-har-credentials-as-placeholders"
    static let importButton = "spec-import-import-button"
    static let importAllButton = "spec-import-import-all-button"
    static let batchSpecCount = "spec-import-batch-spec-count"
    static let batchGroupInOneProject = "spec-import-batch-group-in-one-project"
    static let batchEnvironmentNameField = "spec-import-batch-environment-name"

    static func batchEnvironmentVariable(_ sourceKey: String) -> String {
        let slug = sourceKey
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "spec-import-batch-environment-variable-\(slug)"
    }
    static let cancelButton = "spec-import-cancel-button"
}