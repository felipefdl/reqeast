//
//  SpecImportMapper.swift
//  Reqeast
//

import CryptoKit
import Foundation

// MARK: - Options

enum SpecFolderStrategy: String, Codable, CaseIterable, Hashable {
    case tags
    case paths
    case flat
}

enum SpecRequestNaming: String, Codable, CaseIterable, Hashable {
    case summary
    case operationId
    case methodAndPath
}

enum SpecPreferredBodyContentType: String, Codable, CaseIterable, Hashable {
    case firstListed
    case json = "application/json"
    case urlEncoded = "application/x-www-form-urlencoded"
    case formData = "multipart/form-data"
    case xml = "application/xml"
    case octetStream = "application/octet-stream"
}

enum SpecLinkPreference: String, Codable, CaseIterable, Hashable {
    case linked
    case detached
}

struct SpecImportOptions: Equatable, Hashable {
    var folderStrategy: SpecFolderStrategy = .tags
    var requestNaming: SpecRequestNaming = .summary
    var includeDeprecated: Bool = true
    var enableOptionalParameters: Bool = false
    var scaffoldAuth: Bool = true
    var createEnvironments: Bool = true
    var preferredBodyContentType: SpecPreferredBodyContentType = .firstListed
    var enableSchemaSynthesis: Bool = false
    var importHarCredentialsAsPlaceholders: Bool = false
    var linkToSpec: SpecLinkPreference = .detached

    static let `default` = SpecImportOptions()

    var parseOptions: SpecParseOptions {
        SpecParseOptions(
            enableSchemaSynthesis: enableSchemaSynthesis,
            importHarCredentialsAsPlaceholders: importHarCredentialsAsPlaceholders
        )
    }
}

// MARK: - Result

struct SpecImportMappedResult: Equatable {
    var project: Project
    var folders: [RequestFolder]
    var requests: [Request]
    var environments: [ApiEnvironment]
    /// Mapper-added warnings (e.g. skipped oversized operations).
    var warnings: [SpecWarning]
}

/// Stable UUID derivation for golden tests. Production callers omit this and receive random child IDs.
struct SpecImportIDContext: Equatable, Hashable {
    let projectId: UUID
    let namespace: String

    func uuid(kind: String, name: String) -> UUID {
        SpecImportMapper.deterministicUUID("\(namespace):\(kind):\(name)")
    }
}

// MARK: - Mapper

enum SpecImportMapper {

    private static let recordSizeLimit = CloudSyncService.maxRecordPayloadBytes

    static func map(
        _ result: SpecImportResult,
        projectId: UUID = UUID(),
        options: SpecImportOptions = .default,
        idContext: SpecImportIDContext? = nil
    ) -> SpecImportMappedResult {
        let project = Project(
            id: projectId,
            name: result.project.title
        )

        let folderPlan = buildFolderPlan(from: result.project, options: options)
        let folders = folderPlan.folders.map { entry in
            RequestFolder(
                id: idContext?.uuid(kind: "folder", name: entry.key) ?? UUID(),
                projectId: projectId,
                name: entry.name
            )
        }
        let folderIdByKey = Dictionary(uniqueKeysWithValues: zip(folderPlan.folders.map(\.key), folders.map(\.id)))

        var requests: [Request] = []
        var warnings = result.warnings

        for (index, operation) in result.project.operations.enumerated() {
            if operation.deprecated && !options.includeDeprecated {
                continue
            }

            guard let request = mapOperation(
                operation,
                projectId: projectId,
                folderId: operationFolderId(operation, folderPlan: folderPlan, folderIdByKey: folderIdByKey),
                sortOrder: index,
                options: options,
                idContext: idContext,
                warnings: &warnings
            ) else {
                continue
            }

            if encodedByteCount(request) > recordSizeLimit {
                warnings.append(
                    SpecWarning(
                        code: "RECORD_TOO_LARGE",
                        message: "Skipped \(operation.primaryKey): encoded request exceeds \(recordSizeLimit) bytes",
                        operationRef: operationRef(operation)
                    )
                )
                continue
            }

            requests.append(request)
        }

        let environments: [ApiEnvironment]
        if options.createEnvironments {
            environments = result.project.environments.enumerated().map { index, environment in
                mapEnvironment(
                    environment,
                    projectId: projectId,
                    isActive: index == 0,
                    idContext: idContext
                )
            }
        } else {
            environments = []
        }

        return SpecImportMappedResult(
            project: project,
            folders: folders,
            requests: requests,
            environments: environments,
            warnings: warnings
        )
    }

    // MARK: - Folders

    private struct FolderPlanEntry: Equatable {
        var key: String
        var name: String
        var sortHint: Int
    }

    private struct FolderPlan: Equatable {
        var folders: [FolderPlanEntry]
        var operationFolderKeys: [String: String]
    }

    private static func buildFolderPlan(from project: NormalizedProject, options: SpecImportOptions) -> FolderPlan {
        switch options.folderStrategy {
        case .tags:
            return buildTagFolderPlan(from: project)
        case .paths:
            return buildPathFolderPlan(from: project)
        case .flat:
            return FolderPlan(folders: [], operationFolderKeys: [:])
        }
    }

    private static func buildTagFolderPlan(from project: NormalizedProject) -> FolderPlan {
        let folders = project.folders
            .sorted { $0.sortHint < $1.sortHint }
            .map { folder in
                FolderPlanEntry(key: folder.id, name: folder.name, sortHint: Int(folder.sortHint))
            }

        var operationFolderKeys: [String: String] = [:]
        for operation in project.operations {
            if let folderId = operation.folderId {
                operationFolderKeys[operation.primaryKey] = folderId
            }
        }

        return FolderPlan(folders: folders, operationFolderKeys: operationFolderKeys)
    }

    private static func buildPathFolderPlan(from project: NormalizedProject) -> FolderPlan {
        var folderKeys: [String: FolderPlanEntry] = [:]
        var operationFolderKeys: [String: String] = [:]

        for (index, operation) in project.operations.enumerated() {
            let staticPath = staticPathPrefix(for: operation.path)
            guard !staticPath.isEmpty else { continue }

            let key = "path:\(staticPath)"
            if folderKeys[key] == nil {
                folderKeys[key] = FolderPlanEntry(key: key, name: staticPath, sortHint: index)
            }
            operationFolderKeys[operation.primaryKey] = key
        }

        let folders = folderKeys.values.sorted { $0.sortHint < $1.sortHint }
        return FolderPlan(folders: folders, operationFolderKeys: operationFolderKeys)
    }

    private static func staticPathPrefix(for path: String) -> String {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        var staticSegments: [String] = []

        for segment in segments {
            if segment.isEmpty { continue }
            let text = String(segment)
            if text.hasPrefix("{") && text.hasSuffix("}") {
                continue
            }
            staticSegments.append(text)
        }

        return staticSegments.joined(separator: "/")
    }

    private static func operationFolderId(
        _ operation: NormalizedOperation,
        folderPlan: FolderPlan,
        folderIdByKey: [String: UUID]
    ) -> UUID? {
        guard let folderKey = folderPlan.operationFolderKeys[operation.primaryKey] else {
            return nil
        }
        return folderIdByKey[folderKey]
    }

    // MARK: - Operations

    /// Maps a single normalized HTTP operation to a linked `Request` (sync-added ops).
    static func mapLinkedRequest(
        _ operation: NormalizedOperation,
        projectId: UUID,
        folderId: UUID? = nil,
        sortOrder: Int,
        options: SpecImportOptions = .default
    ) -> Request? {
        var warnings: [SpecWarning] = []
        return mapOperation(
            operation,
            projectId: projectId,
            folderId: folderId,
            sortOrder: sortOrder,
            options: options,
            idContext: nil,
            warnings: &warnings
        )
    }

    /// Maps normalized spec fields to `HttpRequestData` without mutating auth on an existing request.
    static func mapHttpData(
        from operation: NormalizedOperation,
        options: SpecImportOptions = .default
    ) -> HttpRequestData {
        var warnings: [SpecWarning] = []
        return mapHttpData(operation, options: options, warnings: &warnings)
    }

    private static func mapOperation(
        _ operation: NormalizedOperation,
        projectId: UUID,
        folderId: UUID?,
        sortOrder: Int,
        options: SpecImportOptions,
        idContext: SpecImportIDContext?,
        warnings: inout [SpecWarning]
    ) -> Request? {
        switch operation.protocol {
        case .http:
            var request = Request(
                id: idContext?.uuid(kind: "request", name: operation.primaryKey) ?? UUID(),
                projectId: projectId,
                name: requestName(for: operation, options: options),
                type: .http,
                folderId: folderId,
                sortOrder: sortOrder
            )
            request.specIdentity = SpecOperationIdentity(
                primaryKey: operation.primaryKey,
                alternateKeys: operation.alternateKeys
            )
            request.httpData = mapHttpData(
                operation,
                options: options,
                warnings: &warnings
            )
            return request
        case .webSocket:
            var request = Request(
                id: idContext?.uuid(kind: "request", name: operation.primaryKey) ?? UUID(),
                projectId: projectId,
                name: requestName(for: operation, options: options),
                type: .webSocket,
                folderId: folderId,
                sortOrder: sortOrder
            )
            request.specIdentity = SpecOperationIdentity(
                primaryKey: operation.primaryKey,
                alternateKeys: operation.alternateKeys
            )
            request.webSocketData = mapWebSocketData(from: operation)
            return request
        }
    }

    private static func requestName(for operation: NormalizedOperation, options: SpecImportOptions) -> String {
        let baseName: String
        switch options.requestNaming {
        case .summary:
            baseName = operation.name
        case .operationId:
            baseName = operation.primaryKey
        case .methodAndPath:
            baseName = "\(operation.method) \(operation.path)"
        }

        if operation.deprecated && options.includeDeprecated {
            return "[Deprecated] \(baseName)"
        }
        return baseName
    }

    static func mapWebSocketData(from operation: NormalizedOperation) -> WebSocketRequestData {
        let address = operation.binding?.address ?? operation.path
        var data = WebSocketRequestData(
            url: webSocketURL(for: address),
            headers: [KeyValueEntry()]
        )

        let template = operation.binding?.messageTemplate
            ?? webSocketMessageTemplate(from: operation.body)
        if !template.isEmpty {
            data.messageHistory = [
                MessageHistoryEntry(text: template, encoding: .utf8)
            ]
        }

        return data
    }

    private static func webSocketMessageTemplate(from body: NormalizedBody) -> String {
        switch body {
        case .json(let content), .raw(let content, _):
            return content
        default:
            return ""
        }
    }

    private static func webSocketURL(for address: String) -> String {
        guard let schemeRange = address.range(of: "://") else {
            let path = address.hasPrefix("/") ? address : "/\(address)"
            return "{{ws_url}}\(path)"
        }

        let pathStart = address[schemeRange.upperBound...]
        guard let slashIndex = pathStart.firstIndex(of: "/") else {
            return "{{ws_url}}"
        }

        return "{{ws_url}}\(pathStart[slashIndex...])"
    }

    private static func mapHttpData(
        _ operation: NormalizedOperation,
        options: SpecImportOptions,
        warnings: inout [SpecWarning]
    ) -> HttpRequestData {
        if isGraphQLOperation(operation) {
            return mapGraphQLHttpData(operation, options: options, warnings: &warnings)
        }

        var data = HttpRequestData()
        data.method = httpMethod(from: operation.method)
        data.url = requestURL(for: operation.path)
        data.params = mapParams(operation.parameters, options: options)
        data.headers = mapHeaders(operation.parameters, options: options)

        let (body, bodyWarnings) = resolveBody(for: operation, options: options)
        warnings.append(contentsOf: bodyWarnings)
        applyBody(body, to: &data)

        if options.enableSchemaSynthesis {
            warnings.append(contentsOf: synthesizedParameterWarnings(for: operation))
        }

        if options.scaffoldAuth, let auth = operation.auth {
            applyAuth(auth, to: &data)
        }

        return data
    }

    private static func resolveBody(
        for operation: NormalizedOperation,
        options: SpecImportOptions
    ) -> (NormalizedBody, [SpecWarning]) {
        let candidates = operation.bodyCandidates
        guard candidates.count > 1 else {
            return (operation.body, [])
        }

        let opRef = operationRef(operation)
        let alternates = candidates.dropFirst().map(\.contentType).joined(separator: ", ")

        if options.preferredBodyContentType == .firstListed {
            return (
                operation.body,
                [
                    SpecWarning(
                        code: "MULTIPLE_CONTENT_TYPES",
                        message: "Multiple request body content types; using '\(candidates[0].contentType)', alternates: \(alternates)",
                        operationRef: opRef
                    ),
                ]
            )
        }

        let preferred = options.preferredBodyContentType.rawValue
        if let match = candidates.first(where: { contentTypesMatch($0.contentType, preferred) }) {
            return (
                match.body,
                [
                    SpecWarning(
                        code: "MULTIPLE_CONTENT_TYPES",
                        message: "Multiple request body content types; using preferred '\(normalizeContentType(match.contentType))', alternates: \(listedAlternates(for: candidates, selected: match.contentType))",
                        operationRef: opRef
                    ),
                ]
            )
        }

        return (
            operation.body,
            [
                SpecWarning(
                    code: "MULTIPLE_CONTENT_TYPES",
                    message: "Preferred body content type '\(preferred)' not found; using '\(candidates[0].contentType)', alternates: \(alternates)",
                    operationRef: opRef
                ),
            ]
        )
    }

    private static func synthesizedParameterWarnings(for operation: NormalizedOperation) -> [SpecWarning] {
        let opRef = operationRef(operation)
        return operation.parameters.compactMap { parameter in
            guard parameter.valueSource == .synthesized else { return nil }
            return SpecWarning(
                code: "SYNTHESIZED_VALUE",
                message: "Synthesized placeholder value for parameter '\(parameter.name)'",
                operationRef: opRef
            )
        }
    }

    private static func listedAlternates(
        for candidates: [NormalizedBodyCandidate],
        selected: String
    ) -> String {
        candidates
            .map(\.contentType)
            .filter { !contentTypesMatch($0, selected) }
            .joined(separator: ", ")
    }

    private static func contentTypesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizeContentType(lhs).caseInsensitiveCompare(normalizeContentType(rhs)) == .orderedSame
    }

    private static func normalizeContentType(_ contentType: String) -> String {
        contentType
            .split(separator: ";", maxSplits: 1)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? contentType
    }

    private static func isGraphQLOperation(_ operation: NormalizedOperation) -> Bool {
        operation.tags.contains("graphql")
    }

    private static func mapGraphQLHttpData(
        _ operation: NormalizedOperation,
        options: SpecImportOptions,
        warnings: inout [SpecWarning]
    ) -> HttpRequestData {
        var data = HttpRequestData()
        data.method = .post
        data.url = "{{base_url}}"
        data.params = mapGraphQLVariables(operation.parameters, options: options)
        data.headers = [
            KeyValueEntry(key: "Content-Type", value: "application/json", enabled: true),
        ]

        let (body, bodyWarnings) = resolveBody(for: operation, options: options)
        warnings.append(contentsOf: bodyWarnings)
        switch body {
        case .json(let content):
            data.bodyType = .json
            data.bodyContent = syncGraphQLVariables(
                in: content,
                variables: data.params
            )
        default:
            applyBody(body, to: &data)
        }

        return data
    }

    /// GraphQL field arguments are surfaced in the params editor as variable placeholders.
    private static func mapGraphQLVariables(
        _ parameters: [NormalizedParameter],
        options: SpecImportOptions
    ) -> [KeyValueEntry] {
        parameters.map { parameter in
            KeyValueEntry(
                key: parameter.name,
                value: parameter.value,
                enabled: parameterEnabled(parameter, options: options)
            )
        }
    }

    private static func syncGraphQLVariables(
        in bodyContent: String,
        variables: [KeyValueEntry]
    ) -> String {
        guard !variables.isEmpty,
              let data = bodyContent.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return bodyContent
        }

        var variableObject: [String: Any] = [:]
        for entry in variables where entry.enabled {
            variableObject[entry.key] = graphqlVariableValue(entry.value)
        }
        object["variables"] = variableObject

        guard let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: encoded, encoding: .utf8) else {
            return bodyContent
        }
        return text
    }

    private static func graphqlVariableValue(_ raw: String) -> Any {
        if raw == "true" || raw == "false" {
            return raw == "true"
        }
        if let intValue = Int(raw) {
            return intValue
        }
        if let doubleValue = Double(raw), raw.contains(".") {
            return doubleValue
        }
        if raw == "null" {
            return NSNull()
        }
        if raw.hasPrefix("[") || raw.hasPrefix("{") {
            if let data = raw.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                return json
            }
        }
        return raw
    }

    private static func requestURL(for path: String) -> String {
        let templatedPath = path.replacingOccurrences(
            of: #"\{([^}]+)\}"#,
            with: "{{$1}}",
            options: .regularExpression
        )
        return "{{base_url}}\(templatedPath)"
    }

    private static func mapParams(
        _ parameters: [NormalizedParameter],
        options: SpecImportOptions
    ) -> [KeyValueEntry] {
        parameters.compactMap { parameter in
            guard parameter.location == .query || parameter.location == .cookie else {
                return nil
            }
            return KeyValueEntry(
                key: parameter.name,
                value: parameter.value,
                enabled: parameterEnabled(parameter, options: options)
            )
        }
    }

    private static func mapHeaders(
        _ parameters: [NormalizedParameter],
        options: SpecImportOptions
    ) -> [KeyValueEntry] {
        parameters.compactMap { parameter in
            guard parameter.location == .header else {
                return nil
            }
            return KeyValueEntry(
                key: parameter.name,
                value: parameter.value,
                enabled: parameterEnabled(parameter, options: options)
            )
        }
    }

    private static func parameterEnabled(_ parameter: NormalizedParameter, options: SpecImportOptions) -> Bool {
        if parameter.required {
            return true
        }
        if options.enableOptionalParameters {
            return true
        }
        return parameter.enabled
    }

    private static func applyBody(_ body: NormalizedBody, to data: inout HttpRequestData) {
        switch body {
        case .none:
            data.bodyType = .none
        case .json(let content):
            data.bodyType = .json
            data.bodyContent = content
        case .urlencoded(let fields):
            data.bodyType = .urlencoded
            data.bodyFormData = fields.map { field in
                KeyValueEntry(key: field.key, value: field.value, enabled: field.enabled)
            }
        case .formData(let entries):
            data.bodyType = .formData
            data.bodyFormDataEntries = entries.map(mapFormDataEntry)
        case .raw(let content, let contentType):
            data.bodyType = .raw
            data.bodyContent = content
            data.rawContentType = rawContentType(from: contentType)
        case .binary(let fileName):
            data.bodyType = .binary
            data.binaryFileName = fileName
        }
    }

    private static func mapFormDataEntry(_ entry: NormalizedFormDataEntry) -> FormDataEntry {
        FormDataEntry(
            key: entry.key,
            value: entry.value,
            enabled: true,
            fieldType: entry.isFile ? .file : .text,
            fileName: entry.fileName ?? "",
            mimeType: entry.contentType ?? ""
        )
    }

    private static func applyAuth(_ auth: NormalizedAuth, to data: inout HttpRequestData) {
        switch auth.schemeType {
        case "apiKey":
            data.authType = .apiKey
            data.authApiKeyName = auth.headerName ?? auth.queryName ?? ""
            data.authApiKeyValue = auth.placeholderValue
            if auth.headerName != nil {
                data.authApiKeyLocation = "header"
            } else if auth.queryName != nil {
                data.authApiKeyLocation = "query"
            }
        case "http:Bearer", "http:bearer", "openIdConnect":
            data.authType = .bearer
            data.authToken = tokenPlaceholder(from: auth.placeholderValue, prefix: "Bearer ")
        case "http:Basic":
            data.authType = .basic
            parseBasicPlaceholder(auth.placeholderValue, into: &data)
        case "oauth2":
            data.authType = .oauth2
            data.authToken = tokenPlaceholder(from: auth.placeholderValue, prefix: "Bearer ")
            data.authOAuth2GrantType = auth.oauth2GrantType ?? OAuth2GrantType.clientCredentials.rawValue
            data.authOAuth2AuthURL = auth.oauth2AuthUrl ?? ""
            data.authOAuth2TokenURL = auth.oauth2TokenUrl ?? ""
            data.authOAuth2Scopes = auth.oauth2Scopes ?? ""
        default:
            data.authType = .bearer
            data.authToken = auth.placeholderValue
        }
    }

    private static func tokenPlaceholder(from value: String, prefix: String) -> String {
        if value.hasPrefix(prefix) {
            return String(value.dropFirst(prefix.count))
        }
        return value
    }

    private static func parseBasicPlaceholder(_ value: String, into data: inout HttpRequestData) {
        let stripped = value.hasPrefix("Basic ") ? String(value.dropFirst(6)) : value
        let parts = stripped.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            data.authUsername = String(parts[0])
            data.authPassword = String(parts[1])
        } else {
            data.authUsername = "{{username}}"
            data.authPassword = "{{password}}"
        }
    }

    // MARK: - Environments

    private static func mapEnvironment(
        _ environment: NormalizedEnvironment,
        projectId: UUID,
        isActive: Bool,
        idContext: SpecImportIDContext?
    ) -> ApiEnvironment {
        ApiEnvironment(
            id: idContext?.uuid(kind: "environment", name: environment.name) ?? UUID(),
            projectId: projectId,
            name: environment.name,
            variables: environment.variables.map { variable in
                EnvironmentVariable(
                    key: variable.key,
                    value: variable.value,
                    enabled: variable.enabled
                )
            },
            isActive: isActive
        )
    }

    // MARK: - Helpers

    static func deterministicUUID(_ name: String) -> UUID {
        let digest = SHA256.hash(data: Data(name.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }

    private static func httpMethod(from raw: String) -> HttpMethod {
        switch raw.uppercased() {
        case "GET": return .get
        case "POST": return .post
        case "PUT": return .put
        case "PATCH": return .patch
        case "DELETE": return .delete
        case "HEAD": return .head
        case "OPTIONS": return .options
        default: return .get
        }
    }

    private static func rawContentType(from mime: String) -> HttpRawContentType {
        let base = mime.split(separator: ";", maxSplits: 1).first.map(String.init) ?? mime
        switch base.lowercased() {
        case "application/json": return .json
        case "application/xml", "text/xml": return .xml
        case "text/html": return .html
        case "application/javascript", "text/javascript": return .javascript
        default: return .text
        }
    }

    private static func encodedByteCount(_ request: Request) -> Int {
        (try? JSONEncoder().encode(request))?.count ?? 0
    }

    private static func operationRef(_ operation: NormalizedOperation) -> String {
        "\(operation.method.lowercased()) \(operation.path)"
    }
}