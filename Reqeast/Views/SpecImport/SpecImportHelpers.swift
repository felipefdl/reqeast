//
//  SpecImportHelpers.swift
//  Reqeast
//

import Foundation
import UniformTypeIdentifiers

enum SpecImportHelpers {

    static let maxBytes = SafeFetchLimits.maxBodyBytes

    static var specFileTypes: [UTType] {
        [
            UTType(filenameExtension: "yaml") ?? .yaml,
            UTType(filenameExtension: "yml") ?? .yaml,
            .json,
            UTType(filenameExtension: "har") ?? .json,
            UTType(filenameExtension: "graphql") ?? .plainText,
            UTType(filenameExtension: "gql") ?? .plainText,
        ]
    }

    static var specFolderTypes: [UTType] {
        [.folder]
    }

    private static let bundleEntryCandidates = [
        "openapi.yaml",
        "openapi.yml",
        "openapi.json",
        "swagger.yaml",
        "swagger.yml",
        "swagger.json",
    ]

    enum BundleFolderResolution: Equatable {
        case bundle(entry: URL)
        case multiSpec(entries: [URL])
    }

    static func findBundleEntry(in folder: URL) -> URL? {
        guard let resolution = resolveBundleFolder(in: folder) else { return nil }
        switch resolution {
        case .bundle(let entry): return entry
        case .multiSpec: return nil
        }
    }

    static func resolveBundleFolder(in folder: URL) -> BundleFolderResolution? {
        for candidate in bundleEntryCandidates {
            let entry = folder.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: entry.path) {
                return .bundle(entry: entry)
            }
        }

        let discovered = discoverOpenAPIEntryFiles(in: folder)
        switch discovered.count {
        case 0: return nil
        case 1: return .bundle(entry: discovered[0])
        default: return .multiSpec(entries: discovered)
        }
    }

    static func discoverOpenAPIEntryFiles(in folder: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let matches = urls.filter { url in
            guard (try? url.resourceValues(forKeys: keys).isRegularFile) == true else {
                return false
            }
            let name = url.lastPathComponent.lowercased()
            return name.hasSuffix(".openapi.json")
                || name.hasSuffix(".openapi.yaml")
                || name.hasSuffix(".openapi.yml")
        }

        return matches.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    static func sourceFileName(for sourceURL: String?) -> String {
        guard let sourceURL, !sourceURL.isEmpty else { return "" }
        return URL(fileURLWithPath: sourceURL).lastPathComponent
    }

    static func slugStem(fromFileName fileName: String) -> String {
        var stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent.lowercased()
        if stem.hasSuffix(".openapi") {
            stem = String(stem.dropLast(".openapi".count))
        }
        return slugify(stem)
    }

    static func slugify(_ text: String) -> String {
        var result = ""
        var lastUnderscore = false
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                result.append(character)
                lastUnderscore = false
            } else if !lastUnderscore, !result.isEmpty {
                result.append("_")
                lastUnderscore = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    static func defaultBaseURLVariableName(
        fileName: String,
        fallbackTitle: String,
        usedNames: inout Set<String>
    ) -> String {
        var stem = slugStem(fromFileName: fileName)
        if stem.isEmpty {
            stem = slugify(fallbackTitle)
        }
        let base = stem.isEmpty ? "spec_base_url" : "\(stem)_base_url"
        return uniquifyVariableName(base, usedNames: &usedNames)
    }

    static func uniquifyVariableName(_ base: String, usedNames: inout Set<String>) -> String {
        var candidate = base
        var suffix = 2
        let normalizedBase = base.lowercased()
        while usedNames.contains(candidate.lowercased()) {
            candidate = "\(normalizedBase)_\(suffix)"
            suffix += 1
        }
        usedNames.insert(candidate.lowercased())
        return candidate
    }

    static func isValidEnvironmentVariableName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, !trimmed.isEmpty else { return false }
        guard first.isLetter || first == "_" else { return false }
        return trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    static func sourceHint(for url: URL, data: Data) -> SpecSourceHint {
        if isPostmanCollection(data) {
            return .postman
        }
        if isHarLog(data) {
            return .har
        }
        if isGraphQLSDL(data) {
            return .graphql
        }

        switch url.pathExtension.lowercased() {
        case "json": return .json
        case "har": return .har
        case "graphql", "gql": return .graphql
        case "yaml", "yml": return .yaml
        default: return sourceHint(for: data)
        }
    }

    static func sourceHint(for data: Data) -> SpecSourceHint {
        if isPostmanCollection(data) {
            return .postman
        }
        if isHarLog(data) {
            return .har
        }
        if isGraphQLSDL(data) {
            return .graphql
        }

        var index = data.startIndex
        while index < data.endIndex {
            let byte = data[index]
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n")
                || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\t") {
                index = data.index(after: index)
                continue
            }
            return byte == UInt8(ascii: "{") ? .json : .yaml
        }
        return .unknown
    }

    static func detectedFormat(bytes: Data, sourceHint: SpecSourceHint) -> SpecFormat {
        if sourceHint == .postman || isPostmanCollection(bytes) {
            return .postman
        }
        if sourceHint == .har || isHarLog(bytes) {
            return .har
        }
        if sourceHint == .graphql || isGraphQLSDL(bytes) {
            return .graphql
        }
        return .openapi
    }

    static func isGraphQLSDL(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.contains("type Query")
            || text.contains("type Mutation")
            || text.contains("schema {")
            || text.contains("extend type Query")
            || text.contains("extend type Mutation")
    }

    static func isPostmanCollection(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = object["info"] as? [String: Any],
              let schema = info["schema"] as? String else {
            return false
        }
        return schema.localizedCaseInsensitiveContains("postman")
    }

    static func isHarLog(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let log = object["log"] as? [String: Any],
              let version = log["version"] as? String,
              log["entries"] is [Any] else {
            return false
        }
        return version.hasPrefix("1.")
    }

    static func formatLabel(_ format: SpecFormat) -> String {
        switch format {
        case .openapi: String(localized: "OpenAPI")
        case .postman: String(localized: "Postman Collection v2.1")
        case .insomnia: String(localized: "Insomnia")
        case .bruno: String(localized: "Bruno")
        case .graphql: String(localized: "GraphQL")
        case .har: String(localized: "HAR")
        case .asyncApi: String(localized: "AsyncAPI")
        }
    }

    static func formatSystemImage(_ format: SpecFormat) -> String {
        switch format {
        case .postman: "tray.full"
        default: "doc.text"
        }
    }

    static func locksImportTargetToNewProject(_ format: SpecFormat) -> Bool {
        false
    }

    static func sortedImportableProjects(in store: ProjectStore) -> [Project] {
        store.projects
            .filter { $0.deletedAt == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func byteCountLabel(_ count: Int) -> String {
        let limit = ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)
        let current = ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
        return String(localized: "\(current) of \(limit)")
    }

    static func operationCountLabel(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 operation")
            : String(localized: "\(count) operations")
    }

    static func optionsSummary(_ options: SpecImportOptions) -> String {
        [
            options.linkToSpec.localizedName,
            options.folderStrategy.localizedName,
            options.requestNaming.localizedName,
            options.preferredBodyContentType.localizedName,
            options.enableSchemaSynthesis
                ? String(localized: "Schema synthesis on")
                : String(localized: "Schema synthesis off"),
            options.includeDeprecated
                ? String(localized: "Deprecated included")
                : String(localized: "Deprecated excluded"),
            options.enableOptionalParameters
                ? String(localized: "Optional params on")
                : String(localized: "Optional params off"),
            options.scaffoldAuth
                ? String(localized: "Auth scaffold on")
                : String(localized: "Auth scaffold off"),
            options.createEnvironments
                ? String(localized: "Environments on")
                : String(localized: "Environments off"),
            options.importHarCredentialsAsPlaceholders
                ? String(localized: "HAR credentials as placeholders")
                : String(localized: "HAR credentials stripped"),
        ].joined(separator: " · ")
    }
}

extension SpecFolderStrategy {
    var localizedName: String {
        switch self {
        case .tags: String(localized: "Tags")
        case .paths: String(localized: "Paths")
        case .flat: String(localized: "Flat")
        }
    }
}

extension SpecRequestNaming {
    var localizedName: String {
        switch self {
        case .summary: String(localized: "Summary")
        case .operationId: String(localized: "Operation ID")
        case .methodAndPath: String(localized: "Method + Path")
        }
    }
}

extension SpecPreferredBodyContentType {
    var localizedName: String {
        switch self {
        case .firstListed: String(localized: "First listed")
        case .json: String(localized: "JSON")
        case .urlEncoded: String(localized: "URL-encoded")
        case .formData: String(localized: "Form data")
        case .xml: String(localized: "XML")
        case .octetStream: String(localized: "Binary")
        }
    }
}

extension SpecLinkPreference {
    var localizedName: String {
        switch self {
        case .linked: String(localized: "Yes")
        case .detached: String(localized: "Detached")
        }
    }
}