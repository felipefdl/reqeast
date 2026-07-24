//
//  SafeFetchTrustedHosts.swift
//  Reqeast
//
//  User-configured host allowlist for GitHub Enterprise and custom Git hosts.
//  Trusted hosts may use HTTP and resolve to private IPs; all other hosts keep
//  the default HTTPS-only + SSRF blocklist policy (not a global HTTP allow).
//

import Darwin
import Foundation

protocol TrustedHostPolicy: Sendable {
    func isAllowedForGitFetch(_ host: String) -> Bool
    func allowsPrivateIPs(for host: String) -> Bool
    func allowsHTTP(for host: String) -> Bool
}

struct DefaultTrustedHostPolicy: TrustedHostPolicy {
    func isAllowedForGitFetch(_ host: String) -> Bool {
        SafeFetchTrustedHosts.isAllowedForGitFetch(host)
    }

    func allowsPrivateIPs(for host: String) -> Bool {
        SafeFetchTrustedHosts.allowsPrivateIPs(for: host)
    }

    func allowsHTTP(for host: String) -> Bool {
        SafeFetchTrustedHosts.allowsHTTP(for: host)
    }
}

struct FixedTrustedHostPolicy: TrustedHostPolicy {
    let allowedGitHosts: Set<String>
    let privateIPHosts: Set<String>
    let httpHosts: Set<String>

    init(
        allowedGitHosts: Set<String> = [],
        privateIPHosts: Set<String> = [],
        httpHosts: Set<String> = []
    ) {
        self.allowedGitHosts = allowedGitHosts
        self.privateIPHosts = privateIPHosts
        self.httpHosts = httpHosts
    }

    func isAllowedForGitFetch(_ host: String) -> Bool {
        let normalized = SafeFetchTrustedHosts.normalize(host)
        if SafeFetchTrustedHosts.isBuiltInGitHost(normalized) { return true }
        return allowedGitHosts.contains(normalized)
    }

    func allowsPrivateIPs(for host: String) -> Bool {
        privateIPHosts.contains(SafeFetchTrustedHosts.normalize(host))
    }

    func allowsHTTP(for host: String) -> Bool {
        httpHosts.contains(SafeFetchTrustedHosts.normalize(host))
    }
}

enum SafeFetchTrustedHosts {
    static let storageKey = "\(StorageEnvironment.keyPrefix)safeFetchTrustedHosts"

    static var hosts: [String] {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
            return stored.map(normalize).filter { !$0.isEmpty }
        }
        set {
            let normalized = Array(Set(newValue.map(normalize).filter { isValidHostname($0) })).sorted()
            UserDefaults.standard.set(normalized, forKey: storageKey)
        }
    }

    static func isBuiltInGitHost(_ host: String) -> Bool {
        let normalized = normalize(host)
        if normalized == "github.com"
            || normalized == "api.github.com"
            || normalized == "raw.githubusercontent.com" {
            return true
        }
        if normalized.hasSuffix(".github.com"), normalized != "raw.githubusercontent.com" {
            return true
        }
        if normalized == "gitlab.com" || normalized.hasSuffix(".gitlab.com") {
            return true
        }
        return false
    }

    static func isUserTrusted(_ host: String) -> Bool {
        let normalized = normalize(host)
        guard !normalized.isEmpty else { return false }
        return Set(hosts).contains(normalized)
    }

    static func isAllowedForGitFetch(_ host: String) -> Bool {
        isBuiltInGitHost(host) || isUserTrusted(host)
    }

    static func allowsPrivateIPs(for host: String) -> Bool {
        isUserTrusted(host)
    }

    static func allowsHTTP(for host: String) -> Bool {
        isUserTrusted(host)
    }

    @discardableResult
    static func addHost(_ raw: String) -> String? {
        let normalized = normalize(raw)
        guard isValidHostname(normalized) else { return nil }
        var current = Set(hosts)
        guard current.insert(normalized).inserted else { return normalized }
        hosts = Array(current)
        return normalized
    }

    static func removeHost(_ host: String) {
        let normalized = normalize(host)
        hosts = hosts.filter { $0 != normalized }
    }

    static func normalize(_ host: String) -> String {
        var trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            if let url = URL(string: trimmed), let urlHost = url.host {
                trimmed = urlHost
            }
        }
        if let colon = trimmed.firstIndex(of: ":") {
            trimmed = String(trimmed[..<colon])
        }
        if trimmed.hasSuffix(".") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private static func isValidHostname(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253 else { return false }
        guard !host.contains("/") else { return false }

        var v4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 { return false }
        var v6 = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 { return false }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return false }
        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return false }
            guard label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return false }
            guard label.first != "-", label.last != "-" else { return false }
        }
        return true
    }
}