//
//  GitSourceRef.swift
//  Reqeast
//
//  Git spec sources over HTTPS/API (P3). No libgit2 — raw URLs, provider REST, and
//  macOS security-scoped folder bookmarks for re-read on sync.
//

import Foundation
import Security

// MARK: - Types

enum GitProvider: String, Codable, Hashable, CaseIterable {
    case github
    case gitlab
}

/// Git spec source metadata synced on `SpecLink`. Bookmark bytes stay device-local.
struct GitSourceRef: Codable, Hashable {
    var hostBaseURL: String?
    var provider: GitProvider?
    var owner: String?
    var repo: String?
    var ref: String?
    var path: String?
    /// Keychain account key for a non-synced PAT (`GitTokenKeychainService`).
    var tokenKey: String?
}

enum GitImportSource: Equatable {
    case rawHTTPS(url: URL, gitRef: GitSourceRef?)
    case provider(gitRef: GitSourceRef, canonicalURL: String)
}

enum GitSpecSourceError: Error, LocalizedError, Equatable {
    case invalidURL
    case missingGitRef
    case missingBookmark
    case bookmarkAccessFailed
    case tokenRequired
    case unsupportedProvider

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "The Git source URL is invalid.")
        case .missingGitRef:
            String(localized: "Git source metadata is missing.")
        case .missingBookmark:
            String(localized: "The linked folder bookmark could not be found on this device.")
        case .bookmarkAccessFailed:
            String(localized: "Could not access the linked spec folder.")
        case .tokenRequired:
            String(localized: "A personal access token is required for this private repository.")
        case .unsupportedProvider:
            String(localized: "This Git provider is not supported.")
        }
    }
}

// MARK: - URL Parsing

enum GitImportURLParser {

    static func parse(_ urlString: String) -> GitImportSource? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host?.lowercased() else {
            return nil
        }

        if let gitRef = parseGitHubRaw(host: host, url: url, urlString: urlString) {
            return .rawHTTPS(url: url, gitRef: gitRef)
        }
        if let gitRef = parseGitLabRaw(host: host, url: url) {
            return .rawHTTPS(url: url, gitRef: gitRef)
        }
        if let gitRef = parseGitHubBlob(host: host, url: url) {
            return .provider(gitRef: gitRef, canonicalURL: urlString)
        }
        if let gitRef = parseGitHubBlobOnTrustedHost(host: host, url: url) {
            return .provider(gitRef: gitRef, canonicalURL: urlString)
        }
        if let gitRef = parseGitHubRawOnTrustedHost(host: host, url: url, urlString: urlString) {
            return .rawHTTPS(url: url, gitRef: gitRef)
        }
        if let gitRef = parseGitLabBlob(host: host, url: url) {
            return .provider(gitRef: gitRef, canonicalURL: urlString)
        }

        return nil
    }

    private static func parseGitHubRaw(host: String, url: URL, urlString: String) -> GitSourceRef? {
        guard host == "raw.githubusercontent.com" else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 4 else { return nil }

        let owner = parts[0]
        let repo = parts[1]
        // GitHub raw URLs may include an explicit refs/heads|tags prefix:
        // /{owner}/{repo}/refs/heads/{branch}/path or /{owner}/{repo}/{branch}/path
        let ref: String
        let path: String
        if parts.count >= 6,
           parts[2] == "refs",
           parts[3] == "heads" || parts[3] == "tags" {
            ref = parts[4]
            path = parts.dropFirst(5).joined(separator: "/")
        } else {
            ref = parts[2]
            path = parts.dropFirst(3).joined(separator: "/")
        }
        guard !path.isEmpty else { return nil }

        return GitSourceRef(
            hostBaseURL: nil,
            provider: .github,
            owner: owner,
            repo: repo,
            ref: ref,
            path: path,
            tokenKey: GitTokenKeychainService.tokenKey(provider: .github, owner: owner)
        )
    }

    private static func parseGitLabRaw(host: String, url: URL) -> GitSourceRef? {
        guard host == "gitlab.com" || host.hasSuffix(".gitlab.com") else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let rawIndex = parts.firstIndex(of: "-"),
              parts[safe: rawIndex + 1] == "raw",
              rawIndex >= 2 else {
            return nil
        }

        let owner = parts[0]
        let repo = parts[1]
        let ref = parts[rawIndex + 2]
        let path = parts.dropFirst(rawIndex + 3).joined(separator: "/")
        guard !path.isEmpty else { return nil }

        let apiBase = host == "gitlab.com"
            ? "https://gitlab.com/api/v4"
            : "https://\(host)/api/v4"

        return GitSourceRef(
            hostBaseURL: apiBase,
            provider: .gitlab,
            owner: owner,
            repo: repo,
            ref: ref,
            path: path,
            tokenKey: GitTokenKeychainService.tokenKey(provider: .gitlab, owner: owner)
        )
    }

    private static func parseGitHubBlob(host: String, url: URL) -> GitSourceRef? {
        guard host == "github.com" || (host.hasSuffix(".github.com") && host != "raw.githubusercontent.com") else {
            return nil
        }
        return parseGitHubBlobPath(host: host, url: url)
    }

    private static func parseGitHubBlobOnTrustedHost(host: String, url: URL) -> GitSourceRef? {
        guard SafeFetchTrustedHosts.isUserTrusted(host),
              !SafeFetchTrustedHosts.isBuiltInGitHost(host) else {
            return nil
        }
        return parseGitHubBlobPath(host: host, url: url)
    }

    private static func parseGitHubBlobPath(host: String, url: URL) -> GitSourceRef? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 5,
              parts[2] == "blob" else {
            return nil
        }

        let owner = parts[0]
        let repo = parts[1]
        let ref = parts[3]
        let path = parts.dropFirst(4).joined(separator: "/")
        guard !path.isEmpty else { return nil }

        let apiBase = host == "github.com"
            ? "https://api.github.com"
            : "https://\(host)/api/v3"

        return GitSourceRef(
            hostBaseURL: apiBase,
            provider: .github,
            owner: owner,
            repo: repo,
            ref: ref,
            path: path,
            tokenKey: GitTokenKeychainService.tokenKey(provider: .github, owner: owner)
        )
    }

    private static func parseGitHubRawOnTrustedHost(host: String, url: URL, urlString: String) -> GitSourceRef? {
        guard SafeFetchTrustedHosts.isUserTrusted(host),
              !SafeFetchTrustedHosts.isBuiltInGitHost(host) else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 5,
              parts[2] == "raw" else {
            return nil
        }

        let owner = parts[0]
        let repo = parts[1]
        let ref = parts[3]
        let path = parts.dropFirst(4).joined(separator: "/")
        guard !path.isEmpty else { return nil }

        return GitSourceRef(
            hostBaseURL: "https://\(host)/api/v3",
            provider: .github,
            owner: owner,
            repo: repo,
            ref: ref,
            path: path,
            tokenKey: GitTokenKeychainService.tokenKey(provider: .github, owner: owner)
        )
    }

    private static func parseGitLabBlob(host: String, url: URL) -> GitSourceRef? {
        guard host == "gitlab.com" || host.hasSuffix(".gitlab.com") else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let blobIndex = parts.firstIndex(of: "-"),
              parts[safe: blobIndex + 1] == "blob",
              blobIndex >= 2 else {
            return nil
        }

        let owner = parts[0]
        let repo = parts[1]
        let ref = parts[blobIndex + 2]
        let path = parts.dropFirst(blobIndex + 3).joined(separator: "/")
        guard !path.isEmpty else { return nil }

        let apiBase = host == "gitlab.com"
            ? "https://gitlab.com/api/v4"
            : "https://\(host)/api/v4"

        return GitSourceRef(
            hostBaseURL: apiBase,
            provider: .gitlab,
            owner: owner,
            repo: repo,
            ref: ref,
            path: path,
            tokenKey: GitTokenKeychainService.tokenKey(provider: .gitlab, owner: owner)
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Fetch

enum GitSpecSourceService {

    @MainActor
    static func fetchLinkedSpec(specLink: SpecLink, projectId: UUID) async throws -> Data {
        switch specLink.source {
        case .url, .gitHTTPS:
            guard let sourceURL = specLink.sourceURL, let url = URL(string: sourceURL) else {
                throw GitSpecSourceError.invalidURL
            }
            return try await fetchGitURL(url)

        case .gitProvider:
            guard let gitRef = specLink.gitRef else {
                throw GitSpecSourceError.missingGitRef
            }
            return try await fetchProviderSpec(gitRef: gitRef)

        case .localBookmark:
            return try SpecBookmarkStore.readSpecBytes(projectId: projectId).bytes

        case .file, .paste:
            throw GitSpecSourceError.invalidURL
        }
    }

    @MainActor
    static func fetchImportSource(_ source: GitImportSource) async throws -> Data {
        switch source {
        case .rawHTTPS(let url, _):
            return try await fetchGitURL(url)
        case .provider(let gitRef, _):
            return try await fetchProviderSpec(gitRef: gitRef)
        }
    }

    @MainActor
    private static func fetchProviderSpec(gitRef: GitSourceRef) async throws -> Data {
        guard let provider = gitRef.provider else {
            throw GitSpecSourceError.unsupportedProvider
        }

        let requestURL = try providerRequestURL(gitRef: gitRef)
        var headers = providerAcceptHeaders(provider: provider)

        if let tokenKey = gitRef.tokenKey,
           let token = try? GitTokenKeychainService.shared.loadToken(forKey: tokenKey) {
            switch provider {
            case .github:
                headers["Authorization"] = "Bearer \(token)"
            case .gitlab:
                headers["PRIVATE-TOKEN"] = token
            }
        }

        do {
            return try await fetchGitURL(requestURL, headers: headers)
        } catch SafeFetchError.httpError(let statusCode) where statusCode == 401 || statusCode == 403 {
            throw GitSpecSourceError.tokenRequired
        }
    }

    @MainActor
    private static func fetchGitURL(
        _ url: URL,
        headers: [String: String] = [:]
    ) async throws -> Data {
        let requireTrustedHost = gitFetchRequiresTrustedHost(for: url)
        return try await SafeFetchService.shared.fetch(
            url: url,
            requireTrustedHost: requireTrustedHost,
            headers: headers
        )
    }

    private static func gitFetchRequiresTrustedHost(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        return !SafeFetchTrustedHosts.isBuiltInGitHost(host)
    }

    private static func providerRequestURL(gitRef: GitSourceRef) throws -> URL {
        guard let provider = gitRef.provider,
              let owner = gitRef.owner,
              let repo = gitRef.repo,
              let ref = gitRef.ref,
              let path = gitRef.path else {
            throw GitSpecSourceError.missingGitRef
        }

        let apiBase = gitRef.hostBaseURL ?? defaultAPIBase(for: provider)

        switch provider {
        case .github:
            var components = URLComponents(string: "\(apiBase)/repos/\(owner)/\(repo)/contents/\(path)")!
            components.queryItems = [URLQueryItem(name: "ref", value: ref)]
            guard let url = components.url else { throw GitSpecSourceError.invalidURL }
            return url

        case .gitlab:
            let projectPath = "\(owner)/\(repo)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner
            let filePath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            var components = URLComponents(string: "\(apiBase)/projects/\(projectPath)/repository/files/\(filePath)/raw")!
            components.queryItems = [URLQueryItem(name: "ref", value: ref)]
            guard let url = components.url else { throw GitSpecSourceError.invalidURL }
            return url
        }
    }

    private static func defaultAPIBase(for provider: GitProvider) -> String {
        switch provider {
        case .github: "https://api.github.com"
        case .gitlab: "https://gitlab.com/api/v4"
        }
    }

    private static func providerAcceptHeaders(provider: GitProvider) -> [String: String] {
        switch provider {
        case .github:
            ["Accept": "application/vnd.github.raw"]
        case .gitlab:
            [:]
        }
    }

    static func importMetadata(for source: GitImportSource, sourceURL: String) -> (SpecSource, GitSourceRef?) {
        switch source {
        case .rawHTTPS(_, let gitRef):
            (.gitHTTPS, gitRef)
        case .provider(let gitRef, _):
            (.gitProvider, gitRef)
        }
    }
}

// MARK: - PAT Keychain (non-synced)

final class GitTokenKeychainService {
    static let shared = GitTokenKeychainService()

    private let service = "\(StorageEnvironment.keyPrefix)com.reqeast.git.pat"

    private init() {}

    static func tokenKey(provider: GitProvider, owner: String) -> String {
        "\(provider.rawValue):\(owner)"
    }

    func saveToken(_ token: String, forKey key: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unknown(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unknown(updateStatus)
        }
    }

    func loadToken(forKey key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.notFound
            }
            throw KeychainError.unknown(status)
        }

        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return token
    }

    func deleteToken(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unknown(status)
        }
    }

    func deleteAllTokens() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unknown(status)
        }
    }
}

// MARK: - macOS Folder Bookmark (device-local)

struct SpecBookmarkPayload: Equatable {
    var bytes: Data
    var bundleEntryPath: String?
}

enum SpecBookmarkStore {

    #if DEBUG
    static var rootDirectoryOverride: URL? {
        get { _rootDirectoryOverride }
        set { _rootDirectoryOverride = newValue }
    }

    private static var _rootDirectoryOverride: URL?
    #endif

    static func saveBookmark(for projectId: UUID, folderURL: URL) throws {
        #if os(macOS)
        let bookmark = try folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let fileURL = bookmarkFileURL(for: projectId)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bookmark.write(to: fileURL, options: .atomic)
        #else
        _ = projectId
        _ = folderURL
        #endif
    }

    static func deleteBookmark(for projectId: UUID) {
        let fileURL = bookmarkFileURL(for: projectId)
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func readSpecBytes(projectId: UUID) throws -> SpecBookmarkPayload {
        #if os(macOS)
        let fileURL = bookmarkFileURL(for: projectId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw GitSpecSourceError.missingBookmark
        }

        let bookmark = try Data(contentsOf: fileURL)
        var isStale = false
        let resolvedURL = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        let accessed = resolvedURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { resolvedURL.stopAccessingSecurityScopedResource() }
        }
        guard accessed else {
            throw GitSpecSourceError.bookmarkAccessFailed
        }

        guard let entryURL = SpecImportHelpers.findBundleEntry(in: resolvedURL) else {
            throw SpecImportError.from(
                message: String(localized: "No OpenAPI entry file found in the linked folder."),
                kind: .invalidSpec
            )
        }

        let bytes = try Data(contentsOf: entryURL)
        let relativePath = "bundle/\(entryURL.lastPathComponent)"
        return SpecBookmarkPayload(bytes: bytes, bundleEntryPath: relativePath)
        #else
        _ = projectId
        throw GitSpecSourceError.missingBookmark
        #endif
    }

    private static func bookmarkFileURL(for projectId: UUID) -> URL {
        #if DEBUG
        if let override = _rootDirectoryOverride {
            return override.appendingPathComponent("\(projectId.uuidString).bookmark")
        }
        #endif

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("reqeast", isDirectory: true)
            .appendingPathComponent("spec-bookmarks", isDirectory: true)
            .appendingPathComponent("\(projectId.uuidString).bookmark")
    }
}