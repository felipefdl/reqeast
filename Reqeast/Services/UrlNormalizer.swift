//
//  UrlNormalizer.swift
//  Reqeast
//

import Foundation

enum UrlNormalizer {
    static func normalize(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.contains("://") {
            return trimmed
        }

        if isLocal(trimmed) {
            return "http://\(trimmed)"
        }

        if let port = extractPort(from: trimmed) {
            if port == 443 {
                return "https://\(trimmed)"
            }
            return "http://\(trimmed)"
        }

        return "https://\(trimmed)"
    }

    // MARK: - Private

    private static func isLocal(_ url: String) -> Bool {
        let host = extractHost(from: url).lowercased()

        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }

        if host == "[::1]" {
            return true
        }

        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }

        if octets[0] == 127 { return true }
        if octets[0] == 0 && octets[1] == 0 && octets[2] == 0 && octets[3] == 0 { return true }
        if octets[0] == 10 { return true }
        if octets[0] == 192 && octets[1] == 168 { return true }
        if octets[0] == 172 && (16...31).contains(octets[1]) { return true }

        return false
    }

    private static func extractHost(from url: String) -> String {
        let withoutPath = url.split(separator: "/", maxSplits: 1).first.map(String.init) ?? url
        let withoutPort = withoutPath.split(separator: ":", maxSplits: 1).first.map(String.init) ?? withoutPath

        if withoutPath.hasPrefix("[") {
            if let closeBracket = withoutPath.firstIndex(of: "]") {
                return String(withoutPath[...closeBracket])
            }
        }

        return withoutPort
    }

    private static func extractPort(from url: String) -> Int? {
        let withoutPath = url.split(separator: "/", maxSplits: 1).first.map(String.init) ?? url

        if withoutPath.hasPrefix("[") {
            if let closeBracket = withoutPath.firstIndex(of: "]") {
                let afterBracket = withoutPath[withoutPath.index(after: closeBracket)...]
                if afterBracket.hasPrefix(":") {
                    return Int(afterBracket.dropFirst())
                }
            }
            return nil
        }

        let parts = withoutPath.split(separator: ":")
        if parts.count == 2 {
            return Int(parts[1])
        }
        return nil
    }
}
