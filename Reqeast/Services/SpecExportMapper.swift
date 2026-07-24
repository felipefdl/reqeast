//
//  SpecExportMapper.swift
//  Reqeast
//

import Foundation

enum SpecExportMapper {

    private static let deprecatedPrefix = "[Deprecated] "

    static func buildInput(
        project: Project,
        store: ProjectStore,
        options: SpecExportOptions
    ) -> ExportProjectInput {
        let folders = store.requestFolders(for: project.id)
        let environments = options.includeEnvironments
            ? store.environments(for: project.id)
            : []
        let requests = store.requests(for: project.id)
            .filter { $0.type == .http && $0.deletedAt == nil }
            .filter { shouldInclude($0, options: options) }

        return ExportProjectInput(
            title: project.name,
            description: nil,
            version: nil,
            folders: folders.enumerated().map { index, folder in
                mapFolder(folder, sortOrder: UInt32(index))
            },
            operations: requests.compactMap { mapOperation($0) },
            environments: environments.map(mapEnvironment)
        )
    }

    private static func shouldInclude(_ request: Request, options: SpecExportOptions) -> Bool {
        if !options.includeDeprecatedAndStale {
            if request.isSpecStale { return false }
            if isDeprecated(request) { return false }
        }
        return request.httpData != nil
    }

    private static func isDeprecated(_ request: Request) -> Bool {
        request.name.hasPrefix(deprecatedPrefix)
    }

    private static func mapFolder(_ folder: RequestFolder, sortOrder: UInt32) -> ExportFolder {
        ExportFolder(
            id: folder.id.uuidString,
            parentId: nil,
            name: folder.name,
            sortOrder: sortOrder
        )
    }

    private static func mapEnvironment(_ environment: ApiEnvironment) -> ExportEnvironment {
        ExportEnvironment(
            name: environment.name,
            variables: environment.variables.map { variable in
                ExportKeyValue(
                    key: variable.key,
                    value: sanitizedEnvironmentValue(variable),
                    enabled: variable.enabled
                )
            },
            isActive: environment.isActive
        )
    }

    private static func sanitizedEnvironmentValue(_ variable: EnvironmentVariable) -> String {
        guard variable.isSecret, !variable.value.isEmpty else { return variable.value }
        return ""
    }

    /// Maps a normalized spec operation to export IR (align-to-spec path in export review).
    static func mapNormalizedOperation(
        _ operation: NormalizedOperation,
        sortOrder: UInt32
    ) -> ExportOperation? {
        guard operation.protocol == .http else { return nil }

        var request = Request(
            projectId: UUID(),
            name: operation.name,
            type: .http,
            sortOrder: Int(sortOrder)
        )
        request.specIdentity = SpecOperationIdentity(
            primaryKey: operation.primaryKey,
            alternateKeys: operation.alternateKeys
        )
        request.httpData = SpecImportMapper.mapHttpData(from: operation)
        return mapOperation(request)
    }

    private static func mapOperation(_ request: Request) -> ExportOperation? {
        guard let http = request.httpData else { return nil }

        return ExportOperation(
            name: exportName(for: request),
            folderId: request.folderId?.uuidString,
            sortOrder: UInt32(request.sortOrder),
            deprecated: isDeprecated(request),
            description: nil,
            specPrimaryKey: request.specIdentity?.primaryKey,
            requestBodyContentTypes: requestBodyContentTypes(for: http),
            http: mapHttpData(http)
        )
    }

    private static func exportName(for request: Request) -> String {
        if isDeprecated(request), request.name.hasPrefix(deprecatedPrefix) {
            return String(request.name.dropFirst(deprecatedPrefix.count))
        }
        return request.name
    }

    /// Preserves schema-only request bodies when live `HttpRequestData` has no body payload.
    private static func requestBodyContentTypes(for http: HttpRequestData) -> [String] {
        guard http.bodyType == .none else { return [] }

        if let rawContentType = http.rawContentType?.mimeType, !rawContentType.isEmpty {
            return [rawContentType]
        }

        return []
    }

    private static func mapHttpData(_ http: HttpRequestData) -> ExportHttpRequestData {
        ExportHttpRequestData(
            method: http.method.rawLabel,
            url: http.url,
            params: http.params.map(mapKeyValue),
            headers: http.headers.map(mapKeyValue),
            bodyType: mapBodyType(http.bodyType),
            bodyContent: http.bodyContent,
            bodyFormData: http.bodyFormData.map(mapKeyValue),
            bodyFormDataEntries: http.bodyFormDataEntries.map(mapFormDataEntry),
            rawContentType: http.rawContentType?.mimeType ?? "",
            binaryFileName: http.binaryFileName,
            authType: mapAuthType(http.authType),
            authToken: sanitizedAuthValue(http.authToken, placeholder: "{{token}}"),
            authUsername: sanitizedAuthValue(http.authUsername, placeholder: "{{username}}"),
            authPassword: sanitizedAuthValue(http.authPassword, placeholder: "{{password}}"),
            authApiKeyName: http.authApiKeyName,
            authApiKeyValue: sanitizedAuthValue(http.authApiKeyValue, placeholder: "{{api_key}}"),
            authApiKeyLocation: http.authApiKeyLocation
        )
    }

    private static func mapKeyValue(_ entry: KeyValueEntry) -> ExportKeyValue {
        ExportKeyValue(key: entry.key, value: entry.value, enabled: entry.enabled)
    }

    private static func mapFormDataEntry(_ entry: FormDataEntry) -> ExportFormDataEntry {
        ExportFormDataEntry(
            key: entry.key,
            value: entry.value,
            enabled: entry.enabled,
            isFile: entry.fieldType == .file,
            fileName: entry.fileName,
            contentType: entry.mimeType
        )
    }

    private static func mapBodyType(_ bodyType: HttpBodyType) -> ExportBodyType {
        switch bodyType {
        case .none: .none
        case .json: .json
        case .formData: .formData
        case .urlencoded: .urlencoded
        case .raw: .raw
        case .binary: .binary
        }
    }

    private static func mapAuthType(_ authType: HttpAuthType) -> ExportAuthType {
        switch authType {
        case .none: .none
        case .bearer, .jwtBearer: .bearer
        case .basic, .digestAuth: .basic
        case .apiKey: .apiKey
        case .oauth1, .oauth2: .oauth2
        case .hawkAuth, .awsSignature, .akamaiEdgeGrid, .ntlm: .none
        }
    }

    private static func sanitizedAuthValue(_ value: String, placeholder: String) -> String {
        guard !value.isEmpty else { return value }
        if value.contains("{{") { return value }
        return placeholder
    }
}