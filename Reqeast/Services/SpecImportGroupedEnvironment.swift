//
//  SpecImportGroupedEnvironment.swift
//  Reqeast
//

import Foundation

extension SpecImportService {

    static func makeEnvironmentBindings(
        for items: [SpecImportPreview],
        preserving existing: [SpecImportEnvironmentBinding] = []
    ) -> [SpecImportEnvironmentBinding] {
        let preservedNames = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.sourceKey, $0.variableName) }
        )
        var usedNames = Set(existing.map { $0.variableName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var bindings: [SpecImportEnvironmentBinding] = []
        bindings.reserveCapacity(items.count)

        for item in items.sorted(by: {
            sourceSortKey(for: $0).localizedStandardCompare(sourceSortKey(for: $1)) == .orderedAscending
        }) {
            let sourceKey = item.sourceURL ?? item.projectId.uuidString
            let fileName = SpecImportHelpers.sourceFileName(for: item.sourceURL)
            let defaultName: String
            if let preserved = preservedNames[sourceKey] {
                defaultName = preserved
            } else {
                defaultName = SpecImportHelpers.defaultBaseURLVariableName(
                    fileName: fileName,
                    fallbackTitle: item.projectName,
                    usedNames: &usedNames
                )
            }

            bindings.append(
                SpecImportEnvironmentBinding(
                    sourceKey: sourceKey,
                    sourceFileName: fileName.isEmpty ? item.projectName : fileName,
                    specTitle: item.projectName,
                    variableName: defaultName,
                    baseURL: primaryBaseURL(from: item)
                )
            )
        }

        return bindings
    }

    static func validateGroupedEnvironment(
        environmentName: String,
        bindings: [SpecImportEnvironmentBinding]
    ) throws {
        let trimmedEnvironmentName = environmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEnvironmentName.isEmpty else {
            throw SpecImportError.from(
                message: String(localized: "Enter an environment name."),
                kind: .invalidSpec
            )
        }

        guard !bindings.isEmpty else {
            throw SpecImportError.from(
                message: String(localized: "No base URL variables to import."),
                kind: .invalidSpec
            )
        }

        var seenNames: Set<String> = []
        for binding in bindings {
            let trimmedName = binding.variableName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard SpecImportHelpers.isValidEnvironmentVariableName(trimmedName) else {
                throw SpecImportError.from(
                    message: String(
                        localized: "Variable name “\(binding.variableName)” is invalid. Use letters, numbers, and underscores."
                    ),
                    kind: .invalidSpec
                )
            }

            let key = trimmedName.lowercased()
            guard !seenNames.contains(key) else {
                throw SpecImportError.from(
                    message: String(localized: "Variable name “\(trimmedName)” is used more than once."),
                    kind: .invalidSpec
                )
            }
            seenNames.insert(key)
        }
    }

    static func combineGroupedBatch(
        from items: [SpecImportPreview],
        projectId: UUID,
        projectName: String,
        environmentName: String,
        environmentBindings: [SpecImportEnvironmentBinding]
    ) -> SpecImportMappedResult {
        let bindingsBySourceKey = Dictionary(uniqueKeysWithValues: environmentBindings.map { ($0.sourceKey, $0) })
        var folders: [RequestFolder] = []
        var requests: [Request] = []
        var warnings = items.flatMap(\.warnings)
        var folderIdByPrefixedName: [String: UUID] = [:]
        var environmentVariables: [EnvironmentVariable] = []

        for item in items {
            let sourceKey = item.sourceURL ?? item.projectId.uuidString
            guard let binding = bindingsBySourceKey[sourceKey] else { continue }

            let specName = item.projectName
            let variableRemap = variableRemap(for: item, binding: binding)
            var localFolderRemap: [UUID: UUID] = [:]

            for folder in item.mapped.folders {
                let prefixed = prefixedFolderName(specName: specName, folderName: folder.name)
                let key = normalizedFolderName(prefixed)
                let folderId: UUID
                if let existing = folderIdByPrefixedName[key] {
                    folderId = existing
                } else {
                    folderId = UUID()
                    var newFolder = folder
                    newFolder.id = folderId
                    newFolder.projectId = projectId
                    newFolder.name = prefixed
                    folders.append(newFolder)
                    folderIdByPrefixedName[key] = folderId
                }
                localFolderRemap[folder.id] = folderId
            }

            for request in item.mapped.requests {
                var merged = rewriteRequestVariables(request, remap: variableRemap)
                merged.id = UUID()
                merged.projectId = projectId
                if let folderId = request.folderId {
                    merged.folderId = localFolderRemap[folderId]
                }
                requests.append(merged)
            }

            environmentVariables.append(
                contentsOf: groupedEnvironmentVariables(for: item, binding: binding, variableRemap: variableRemap)
            )
        }

        let environment = ApiEnvironment(
            projectId: projectId,
            name: environmentName.trimmingCharacters(in: .whitespacesAndNewlines),
            variables: environmentVariables,
            isActive: true
        )

        var project = Project(id: projectId, name: projectName)
        if let iconURL = items.compactMap(\.mapped.project.iconURL).first {
            project.iconURL = iconURL
        }

        return SpecImportMappedResult(
            project: project,
            folders: folders,
            requests: requests,
            environments: [environment],
            warnings: warnings
        )
    }

    // MARK: - Private

    private static func sourceSortKey(for item: SpecImportPreview) -> String {
        let fileName = SpecImportHelpers.sourceFileName(for: item.sourceURL)
        return fileName.isEmpty ? item.projectName : fileName
    }

    private static func primaryBaseURL(from item: SpecImportPreview) -> String {
        for environment in item.mapped.environments {
            if let baseURL = environment.variables.first(where: { $0.key == "base_url" && $0.enabled }) {
                return baseURL.value
            }
        }
        return "/"
    }

    private static func slugPrefix(for variableName: String) -> String {
        if variableName.hasSuffix("_base_url") {
            return String(variableName.dropLast("_base_url".count))
        }
        return SpecImportHelpers.slugify(variableName)
    }

    private static func variableRemap(
        for item: SpecImportPreview,
        binding: SpecImportEnvironmentBinding
    ) -> [String: String] {
        var remap = ["base_url": binding.variableName.trimmingCharacters(in: .whitespacesAndNewlines)]
        let prefix = slugPrefix(for: remap["base_url"] ?? "")
        guard !prefix.isEmpty else { return remap }

        for environment in item.mapped.environments {
            for variable in environment.variables where variable.key != "base_url" {
                remap[variable.key] = "\(prefix)_\(variable.key)"
            }
        }
        return remap
    }

    private static func groupedEnvironmentVariables(
        for item: SpecImportPreview,
        binding: SpecImportEnvironmentBinding,
        variableRemap: [String: String]
    ) -> [EnvironmentVariable] {
        var variables: [EnvironmentVariable] = []
        var seenKeys: Set<String> = []

        for environment in item.mapped.environments {
            for variable in environment.variables {
                guard let mappedKey = variableRemap[variable.key] else { continue }
                let normalized = mappedKey.lowercased()
                guard !seenKeys.contains(normalized) else { continue }
                seenKeys.insert(normalized)

                let value = variable.key == "base_url" ? binding.baseURL : variable.value
                variables.append(
                    EnvironmentVariable(
                        key: mappedKey,
                        value: value,
                        isSecret: variable.isSecret,
                        enabled: variable.enabled
                    )
                )
            }
        }

        if !seenKeys.contains(binding.variableName.lowercased()) {
            variables.insert(
                EnvironmentVariable(
                    key: binding.variableName.trimmingCharacters(in: .whitespacesAndNewlines),
                    value: binding.baseURL,
                    enabled: true
                ),
                at: 0
            )
        }

        return variables
    }

    private static func rewriteRequestVariables(_ request: Request, remap: [String: String]) -> Request {
        var updated = request
        if var httpData = updated.httpData {
            httpData.url = rewriteTemplateVariables(in: httpData.url, remap: remap)
            httpData.params = rewriteEntries(httpData.params, remap: remap)
            httpData.headers = rewriteEntries(httpData.headers, remap: remap)
            httpData.bodyContent = rewriteTemplateVariables(in: httpData.bodyContent, remap: remap)
            httpData.bodyFormData = rewriteEntries(httpData.bodyFormData, remap: remap)
            httpData.authToken = rewriteTemplateVariables(in: httpData.authToken, remap: remap)
            httpData.authUsername = rewriteTemplateVariables(in: httpData.authUsername, remap: remap)
            httpData.authPassword = rewriteTemplateVariables(in: httpData.authPassword, remap: remap)
            httpData.authApiKeyValue = rewriteTemplateVariables(in: httpData.authApiKeyValue, remap: remap)
            httpData.authOAuth2AuthURL = rewriteTemplateVariables(in: httpData.authOAuth2AuthURL, remap: remap)
            httpData.authOAuth2TokenURL = rewriteTemplateVariables(in: httpData.authOAuth2TokenURL, remap: remap)
            updated.httpData = httpData
        }

        if var webSocketData = updated.webSocketData {
            webSocketData.url = rewriteTemplateVariables(in: webSocketData.url, remap: remap)
            webSocketData.headers = rewriteEntries(webSocketData.headers, remap: remap)
            updated.webSocketData = webSocketData
        }

        if var sseData = updated.sseData {
            sseData.url = rewriteTemplateVariables(in: sseData.url, remap: remap)
            sseData.headers = rewriteEntries(sseData.headers, remap: remap)
            updated.sseData = sseData
        }

        return updated
    }

    private static func rewriteEntries(_ entries: [KeyValueEntry], remap: [String: String]) -> [KeyValueEntry] {
        entries.map { entry in
            var updated = entry
            updated.value = rewriteTemplateVariables(in: entry.value, remap: remap)
            return updated
        }
    }

    private static func rewriteTemplateVariables(in text: String, remap: [String: String]) -> String {
        guard text.contains("{{") else { return text }

        var result = text
        for (oldKey, newKey) in remap.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(of: "{{\(oldKey)}}", with: "{{\(newKey)}}")
        }
        return result
    }

    private static func prefixedFolderName(specName: String, folderName: String) -> String {
        let trimmedSpec = specName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFolder = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFolder.isEmpty else { return trimmedSpec }
        if trimmedFolder.caseInsensitiveCompare(trimmedSpec) == .orderedSame {
            return trimmedSpec
        }
        return "\(trimmedSpec) / \(trimmedFolder)"
    }

    private static func normalizedFolderName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}