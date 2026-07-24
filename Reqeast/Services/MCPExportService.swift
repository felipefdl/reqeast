//
//  MCPExportService.swift
//  Reqeast
//

#if os(macOS)

import Foundation
import os

private let logger = Logger(subsystem: "app.reqeast", category: "MCPExport")

@MainActor
final class MCPExportService {
    static let shared = MCPExportService()
    static let enabledKey = "mcpExportEnabled"

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    #if DEBUG
    /// Isolated MCP output directory for unit tests (avoids parallel suite races on `projects.json`).
    static var mcpDirectoryOverride: URL?
    #endif

    private var sessionsDir: String
    private var recentExecutions: [RecentExecution] = []
    private var contextDebounce: Task<Void, Never>?
    private var projectsDebounce: Task<Void, Never>?
    private var environmentsDebounce: Task<Void, Never>?

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    private init() {
        sessionsDir = StorageEnvironment.sessionsDirName
        try? FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
    }

    private var mcpDirectory: URL {
        Self.resolveMcpDirectory()
    }

    private static func resolveMcpDirectory() -> URL {
        #if DEBUG
        if let override = mcpDirectoryOverride {
            return override
        }
        #endif
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let subdirectory = StorageEnvironment.mcpDirName
        return appSupport
            .appendingPathComponent("reqeast", isDirectory: true)
            .appendingPathComponent(subdirectory, isDirectory: true)
    }

    // MARK: - Context Export

    func exportContext(projectId: UUID?, requestId: UUID?) {
        guard isEnabled else { return }
        if StorageEnvironment.isScreenshotMode { return }
        contextDebounce?.cancel()
        contextDebounce = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            writeContext(projectId: projectId, requestId: requestId)
        }
    }

    func recordExecution(
        requestId: UUID,
        requestName: String,
        projectName: String,
        method: String,
        url: String,
        statusCode: Int,
        elapsedMs: Double
    ) {
        guard isEnabled else { return }
        let entry = RecentExecution(
            requestId: requestId.uuidString,
            requestName: requestName,
            projectName: projectName,
            method: method,
            url: url,
            statusCode: statusCode,
            elapsedMs: elapsedMs,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        recentExecutions.append(entry)
        if recentExecutions.count > 10 {
            recentExecutions.removeFirst(recentExecutions.count - 10)
        }
        contextDebounce?.cancel()
        contextDebounce = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            writeContext(projectId: nil, requestId: nil)
        }
    }

    // MARK: - Projects Export

    func exportProjects(store: ProjectStore) {
        guard isEnabled else { return }
        // Screenshot / UITest launches load demo data in App.init. Skip disk export so
        // we do not race the first frame or thrash Application Support under capture.
        if StorageEnvironment.isScreenshotMode { return }
        projectsDebounce?.cancel()
        projectsDebounce = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            writeProjects(store: store)
        }
    }

    #if DEBUG
    /// Synchronous export for unit tests (avoids debounce races between serialized cases).
    func flushProjectsExportForTesting(store: ProjectStore) {
        projectsDebounce?.cancel()
        projectsDebounce = nil
        writeProjects(store: store)
    }
    #endif

    // MARK: - Response Metadata Export

    func exportResponseMeta(requestId: UUID, response: HttpResponseData) {
        guard isEnabled else { return }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let sessionsDirectory = appSupport
            .appendingPathComponent("reqeast", isDirectory: true)
            .appendingPathComponent(sessionsDir, isDirectory: true)

        let meta = MCPResponseMetaExport(
            statusCode: response.statusCode,
            statusText: response.statusText,
            headers: response.headers.map { MCPKeyValueExport(key: $0.key, value: $0.value, enabled: $0.enabled) },
            elapsedMs: response.elapsedMs,
            bodySize: response.bodySize,
            finalUrl: response.finalUrl,
            httpVersion: response.httpVersion,
            remoteAddr: response.remoteAddr,
            timestamp: ISO8601DateFormatter().string(from: response.timestamp),
            timing: response.timing.map {
                MCPTimingExport(dnsLookupMs: $0.dnsLookupMs, connectionMs: $0.connectionMs, downloadMs: $0.downloadMs, totalMs: $0.totalMs)
            },
            certificate: response.certificate.map {
                MCPCertificateExport(subjectCn: $0.subjectCn, issuerCn: $0.issuerCn, validUntil: $0.validUntil)
            },
            sizeInfo: response.sizeInfo.map {
                MCPSizeInfoExport(
                    requestHeadersSize: $0.requestHeadersSize, requestBodySize: $0.requestBodySize,
                    responseHeadersSize: $0.responseHeadersSize, responseBodySize: $0.responseBodySize,
                    responseCompressedSize: $0.responseCompressedSize
                )
            },
            redirectChain: response.redirectChain.map {
                MCPRedirectExport(url: $0.url, statusCode: $0.statusCode)
            }
        )

        do {
            let data = try encoder.encode(meta)
            let url = sessionsDirectory.appendingPathComponent("\(requestId.uuidString)-response-meta.json")
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to write response meta: \(error)")
        }
    }

    // MARK: - Environments Export

    func exportEnvironments(environments: [ApiEnvironment]) {
        guard isEnabled else { return }
        if StorageEnvironment.isScreenshotMode { return }
        environmentsDebounce?.cancel()
        environmentsDebounce = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            writeEnvironments(environments: environments)
        }
    }

    // MARK: - Private Writers

    private func writeContext(projectId: UUID?, requestId: UUID?) {
        let context = MCPContextExport(
            version: 1,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            sessionsDir: sessionsDir,
            selectedProjectId: projectId?.uuidString,
            selectedRequestId: requestId?.uuidString,
            recentExecutions: recentExecutions
        )
        writeJSON(context, to: "context.json")
    }

    private func writeProjects(store: ProjectStore) {
        let exportedRequests = store.requests.filter({ $0.deletedAt == nil }).map { request -> MCPRequestExport in
            MCPRequestExport(
                id: request.id.uuidString,
                projectId: request.projectId.uuidString,
                name: request.name,
                type: request.type.rawValue,
                folderId: request.folderId?.uuidString,
                sortOrder: request.sortOrder,
                httpData: request.httpData.map { stripCredentials($0) },
                tcpData: request.tcpData.map { MCPTcpDataExport(host: $0.host, port: $0.port, useTls: $0.useTls, encoding: $0.encoding.rawValue) },
                udpData: request.udpData.map { MCPUdpDataExport(host: $0.host, port: $0.port, bindPort: $0.bindPort ?? 0, timeout: $0.timeoutSeconds) }
            )
        }

        let export = MCPProjectsExport(
            version: 1,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            projects: store.projects.filter({ $0.deletedAt == nil }).map {
                MCPProjectEntry(
                    id: $0.id.uuidString,
                    name: $0.name,
                    emoji: $0.emoji,
                    iconURL: $0.iconURL,
                    color: $0.color.rawValue,
                    folderId: $0.folderId?.uuidString
                )
            },
            requests: exportedRequests,
            requestFolders: store.requestFolders.filter({ $0.deletedAt == nil }).map {
                MCPRequestFolderEntry(
                    id: $0.id.uuidString,
                    projectId: $0.projectId.uuidString,
                    name: $0.name,
                    color: $0.color.rawValue
                )
            }
        )
        writeJSON(export, to: "projects.json")
    }

    private func writeEnvironments(environments: [ApiEnvironment]) {
        let export = MCPEnvironmentsExport(
            version: 1,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            environments: environments.map { env in
                MCPEnvironmentEntry(
                    id: env.id.uuidString,
                    projectId: env.projectId.uuidString,
                    name: env.name,
                    variables: env.variables.map { v in
                        MCPEnvironmentVariableEntry(
                            key: v.key,
                            value: v.isSecret ? "[REDACTED]" : v.value,
                            isSecret: v.isSecret,
                            enabled: v.enabled
                        )
                    },
                    isActive: env.isActive
                )
            }
        )
        writeJSON(export, to: "environments.json")
    }

    private static let sensitiveHeaderNames: Set<String> = [
        "authorization",
        "cookie",
        "x-api-key",
    ]

    private static let sensitiveParamNames: Set<String> = [
        "api_key",
    ]

    private func stripCredentials(_ data: HttpRequestData) -> MCPHttpDataExport {
        MCPHttpDataExport(
            method: data.method.rawLabel,
            url: data.url,
            params: data.params
                .filter { !Self.sensitiveParamNames.contains($0.key.lowercased()) }
                .map { MCPKeyValueExport(key: $0.key, value: $0.value, enabled: $0.enabled) },
            headers: data.headers
                .filter { !Self.sensitiveHeaderNames.contains($0.key.lowercased()) }
                .map { MCPKeyValueExport(key: $0.key, value: $0.value, enabled: $0.enabled) },
            bodyType: data.bodyType.rawValue,
            bodyContent: data.bodyContent,
            bodyFormData: data.bodyFormData.map { MCPKeyValueExport(key: $0.key, value: $0.value, enabled: $0.enabled) },
            authType: data.authType.rawValue,
            followRedirects: data.followRedirects,
            timeoutSeconds: data.timeoutSeconds,
            sslVerify: data.sslVerify,
            httpVersion: data.httpVersion,
            maxRedirects: data.maxRedirects,
            encodeUrl: data.encodeUrl
        )
    }

    private func writeJSON<T: Encodable>(_ value: T, to filename: String) {
        do {
            let data = try encoder.encode(value)
            let directory = mcpDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to write MCP export \(filename): \(error)")
        }
    }
}

// MARK: - Export Structs

private struct MCPContextExport: Encodable {
    let version: Int
    let timestamp: String
    let sessionsDir: String
    let selectedProjectId: String?
    let selectedRequestId: String?
    let recentExecutions: [RecentExecution]
}

private struct RecentExecution: Encodable {
    let requestId: String
    let requestName: String
    let projectName: String
    let method: String
    let url: String
    let statusCode: Int
    let elapsedMs: Double
    let timestamp: String
}

private struct MCPProjectsExport: Encodable {
    let version: Int
    let timestamp: String
    let projects: [MCPProjectEntry]
    let requests: [MCPRequestExport]
    let requestFolders: [MCPRequestFolderEntry]
}

private struct MCPProjectEntry: Encodable {
    let id: String
    let name: String
    let emoji: String?
    let iconURL: String?
    let color: String
    let folderId: String?
}

private struct MCPRequestExport: Encodable {
    let id: String
    let projectId: String
    let name: String
    let type: String
    let folderId: String?
    let sortOrder: Int
    let httpData: MCPHttpDataExport?
    let tcpData: MCPTcpDataExport?
    let udpData: MCPUdpDataExport?
}

private struct MCPHttpDataExport: Encodable {
    let method: String
    let url: String
    let params: [MCPKeyValueExport]
    let headers: [MCPKeyValueExport]
    let bodyType: String
    let bodyContent: String
    let bodyFormData: [MCPKeyValueExport]
    let authType: String
    let followRedirects: Bool
    let timeoutSeconds: Int
    let sslVerify: Bool
    let httpVersion: String
    let maxRedirects: Int
    let encodeUrl: Bool
}

private struct MCPTcpDataExport: Encodable {
    let host: String
    let port: Int
    let useTls: Bool
    let encoding: String
}

private struct MCPUdpDataExport: Encodable {
    let host: String
    let port: Int
    let bindPort: Int
    let timeout: Int
}

private struct MCPKeyValueExport: Encodable {
    let key: String
    let value: String
    let enabled: Bool
}

private struct MCPRequestFolderEntry: Encodable {
    let id: String
    let projectId: String
    let name: String
    let color: String
}

private struct MCPEnvironmentsExport: Encodable {
    let version: Int
    let timestamp: String
    let environments: [MCPEnvironmentEntry]
}

private struct MCPEnvironmentEntry: Encodable {
    let id: String
    let projectId: String
    let name: String
    let variables: [MCPEnvironmentVariableEntry]
    let isActive: Bool
}

private struct MCPEnvironmentVariableEntry: Encodable {
    let key: String
    let value: String
    let isSecret: Bool
    let enabled: Bool
}

private struct MCPResponseMetaExport: Encodable {
    let statusCode: Int
    let statusText: String
    let headers: [MCPKeyValueExport]
    let elapsedMs: Double
    let bodySize: Int64
    let finalUrl: String
    let httpVersion: String
    let remoteAddr: String?
    let timestamp: String
    let timing: MCPTimingExport?
    let certificate: MCPCertificateExport?
    let sizeInfo: MCPSizeInfoExport?
    let redirectChain: [MCPRedirectExport]
}

private struct MCPTimingExport: Encodable {
    let dnsLookupMs: Double
    let connectionMs: Double
    let downloadMs: Double
    let totalMs: Double
}

private struct MCPCertificateExport: Encodable {
    let subjectCn: String?
    let issuerCn: String?
    let validUntil: String?
}

private struct MCPSizeInfoExport: Encodable {
    let requestHeadersSize: Int64
    let requestBodySize: Int64
    let responseHeadersSize: Int64
    let responseBodySize: Int64
    let responseCompressedSize: Int64
}

private struct MCPRedirectExport: Encodable {
    let url: String
    let statusCode: Int
}

#endif
