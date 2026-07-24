//
//  GitOAuthService.swift
//  Reqeast
//
//  GitHub OAuth Device Authorization Grant for PAT acquisition (AC27).
//  Tokens are stored in GitTokenKeychainService (non-synced) and consumed by
//  GitSpecSourceService when fetching linked provider specs (T42).
//

import Foundation

// MARK: - Configuration

enum GitOAuthConfiguration: Sendable {
    /// OAuth scope for reading private repository contents via the GitHub API.
    static let githubScope = "repo"

    /// Public client identifier for the Reqeast GitHub OAuth App (device flow enabled).
    /// Override via Info.plist `GitHubOAuthClientID` or `REQEAST_GITHUB_OAUTH_CLIENT_ID`.
    nonisolated static var githubClientID: String {
        if let env = ProcessInfo.processInfo.environment["REQEAST_GITHUB_OAUTH_CLIENT_ID"],
           !env.isEmpty {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String,
           !plist.isEmpty {
            return plist
        }
        return "Iv1.8a61f03b3a7aba76"
    }
}

// MARK: - Models

struct GitDeviceCodeSession: Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let verificationURIComplete: URL?
    let expiresIn: TimeInterval
    let interval: TimeInterval
    let host: String?
}

struct GitOAuthAccount: Codable, Hashable, Identifiable, Sendable {
    var provider: GitProvider
    var owner: String
    var host: String?

    var id: String {
        let hostPart = host ?? "github.com"
        return "\(provider.rawValue):\(owner)@\(hostPart)"
    }

    var tokenKey: String {
        GitTokenKeychainService.tokenKey(provider: provider, owner: owner)
    }

    var displayHost: String {
        host ?? "github.com"
    }
}

enum GitOAuthError: Error, LocalizedError, Equatable {
    case missingClientID
    case invalidResponse
    case httpError(statusCode: Int)
    case authorizationPending
    case slowDown
    case expiredToken
    case accessDenied
    case hostNotAllowed(String)
    case pollingCancelled
    case providerError(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            String(localized: "GitHub OAuth is not configured.")
        case .invalidResponse:
            String(localized: "Received an invalid response from the Git provider.")
        case .httpError(let statusCode):
            String(localized: "Git provider returned HTTP error \(statusCode).")
        case .authorizationPending:
            String(localized: "Waiting for authorization on GitHub.")
        case .slowDown:
            String(localized: "Polling too quickly. Slowing down.")
        case .expiredToken:
            String(localized: "The device authorization code expired. Try again.")
        case .accessDenied:
            String(localized: "Authorization was denied on GitHub.")
        case .hostNotAllowed(let host):
            String(
                localized: "Host \(host) is not allowed. Add it under Settings → Trusted Git Hosts."
            )
        case .pollingCancelled:
            String(localized: "GitHub sign-in was cancelled.")
        case .providerError(let message):
            message
        }
    }
}

// MARK: - Account Registry

enum GitOAuthAccountRegistry {
    static let storageKey = "\(StorageEnvironment.keyPrefix)gitOAuthAccounts"

    static func accounts() -> [GitOAuthAccount] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([GitOAuthAccount].self, from: data)) ?? []
    }

    static func register(_ account: GitOAuthAccount) {
        var current = accounts()
        current.removeAll { $0.id == account.id }
        current.append(account)
        current.sort { $0.owner.localizedCaseInsensitiveCompare($1.owner) == .orderedAscending }
        save(current)
    }

    static func remove(_ account: GitOAuthAccount) {
        var current = accounts()
        current.removeAll { $0.id == account.id }
        save(current)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func save(_ accounts: [GitOAuthAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - HTTP Client

protocol GitOAuthHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionGitOAuthHTTPClient: GitOAuthHTTPClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

// MARK: - Service

@MainActor
final class GitOAuthService {
    static let shared = GitOAuthService()

    #if DEBUG
    static var sharedOverride: GitOAuthService?
    static var current: GitOAuthService { sharedOverride ?? shared }
    #else
    static var current: GitOAuthService { shared }
    #endif

    private let httpClient: GitOAuthHTTPClient
    private let keychain: GitOAuthKeychainProviding
    private let clientIDProvider: @Sendable () -> String

    init(
        httpClient: GitOAuthHTTPClient = URLSessionGitOAuthHTTPClient(),
        keychain: GitOAuthKeychainProviding = GitTokenKeychainService.shared,
        clientIDProvider: @escaping @Sendable () -> String = { GitOAuthConfiguration.githubClientID }
    ) {
        self.httpClient = httpClient
        self.keychain = keychain
        self.clientIDProvider = clientIDProvider
    }

    func hasStoredToken(for account: GitOAuthAccount) -> Bool {
        (try? keychain.loadToken(forKey: account.tokenKey)) != nil
    }

    func saveManualToken(_ token: String, account: GitOAuthAccount) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitOAuthError.providerError(String(localized: "Token cannot be empty."))
        }
        try keychain.saveToken(trimmed, forKey: account.tokenKey)
        GitOAuthAccountRegistry.register(account)
    }

    func deleteToken(for account: GitOAuthAccount) throws {
        try keychain.deleteToken(forKey: account.tokenKey)
        GitOAuthAccountRegistry.remove(account)
    }

    func requestDeviceCode(account: GitOAuthAccount) async throws -> GitDeviceCodeSession {
        let clientID = try resolvedClientID()
        let host = try resolvedHost(for: account)
        let url = oauthURL(path: "login/device/code", host: host)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = formEncoded([
            "client_id": clientID,
            "scope": GitOAuthConfiguration.githubScope,
        ])
        request.httpBody = Data(body.utf8)

        let data = try await performRequest(request)
        let json = try decodeJSONObject(data)

        guard let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let verificationURIString = json["verification_uri"] as? String,
              let verificationURI = URL(string: verificationURIString),
              let expiresIn = json["expires_in"] as? Int,
              let interval = json["interval"] as? Int else {
            throw GitOAuthError.invalidResponse
        }

        let verificationURIComplete = (json["verification_uri_complete"] as? String).flatMap(URL.init(string:))

        return GitDeviceCodeSession(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: verificationURI,
            verificationURIComplete: verificationURIComplete,
            expiresIn: TimeInterval(expiresIn),
            interval: TimeInterval(interval),
            host: account.host
        )
    }

    func pollForAccessToken(
        session: GitDeviceCodeSession,
        shouldContinue: @escaping @Sendable () -> Bool = { true }
    ) async throws -> String {
        let clientID = try resolvedClientID()
        let host = try resolvedHost(host: session.host)
        let url = oauthURL(path: "login/oauth/access_token", host: host)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = formEncoded([
            "client_id": clientID,
            "device_code": session.deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
        request.httpBody = Data(body.utf8)

        let deadline = Date().addingTimeInterval(session.expiresIn)
        var interval = max(session.interval, 1)

        while Date() < deadline {
            try Task.checkCancellation()
            guard shouldContinue() else { throw GitOAuthError.pollingCancelled }

            let data = try await performRequest(request)
            let json = try decodeJSONObject(data)

            if let accessToken = json["access_token"] as? String, !accessToken.isEmpty {
                return accessToken
            }

            if let error = json["error"] as? String {
                switch error {
                case "authorization_pending":
                    break
                case "slow_down":
                    interval += 5
                case "expired_token":
                    throw GitOAuthError.expiredToken
                case "access_denied":
                    throw GitOAuthError.accessDenied
                default:
                    let description = json["error_description"] as? String
                    throw GitOAuthError.providerError(description ?? error)
                }
            } else {
                throw GitOAuthError.invalidResponse
            }

            try await Task.sleep(for: .seconds(interval))
        }

        throw GitOAuthError.expiredToken
    }

    func completeDeviceFlow(account: GitOAuthAccount, session: GitDeviceCodeSession) async throws {
        let token = try await pollForAccessToken(session: session)
        try saveManualToken(token, account: account)
    }

    // MARK: - Private

    private func resolvedClientID() throws -> String {
        let clientID = clientIDProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw GitOAuthError.missingClientID }
        return clientID
    }

    private func resolvedHost(for account: GitOAuthAccount) throws -> String {
        try resolvedHost(host: account.host)
    }

    private func resolvedHost(host: String?) throws -> String {
        let normalized = host.map(SafeFetchTrustedHosts.normalize)
        if let normalized, !normalized.isEmpty {
            guard SafeFetchTrustedHosts.isAllowedForGitFetch(normalized) else {
                throw GitOAuthError.hostNotAllowed(normalized)
            }
            return normalized
        }
        return "github.com"
    }

    private func oauthURL(path: String, host: String) -> URL {
        URL(string: "https://\(host)/\(path)")!
    }

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await httpClient.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitOAuthError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw GitOAuthError.httpError(statusCode: http.statusCode)
        }
        return data
    }

    private func decodeJSONObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else {
            throw GitOAuthError.invalidResponse
        }
        return json
    }

    private func formEncoded(_ fields: [String: String]) -> String {
        fields.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        .joined(separator: "&")
    }
}

// MARK: - Test seam

protocol GitOAuthKeychainProviding: Sendable {
    func saveToken(_ token: String, forKey key: String) throws
    func loadToken(forKey key: String) throws -> String
    func deleteToken(forKey key: String) throws
}

extension GitTokenKeychainService: GitOAuthKeychainProviding {}