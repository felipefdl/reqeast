//
//  ProjectIconResolver.swift
//  Reqeast
//

import Foundation

enum ProjectIconResolver {

    /// Ordered HTTPS icon URL candidates: website favicons first, OpenAPI `x-logo` last.
    static func candidateURLs(specIconURL: String?, sourceURL: String?) async -> [String] {
        var discovered: [String] = []
        // Unit tests stay offline and deterministic: use only the parsed spec icon.
        if !StorageEnvironment.isRunningTests {
            for origin in websiteOrigins(specIconURL: specIconURL, sourceURL: sourceURL) {
                discovered.append(contentsOf: await discoverFavicons(for: origin))
            }
        }
        return buildCandidateURLs(
            specIconURL: specIconURL,
            discoveredFavicons: discovered
        )
    }

    /// Returns the first candidate that downloads as a valid image. Failures are non-fatal.
    /// In unit tests, return the first candidate without probing the network.
    static func resolveFirstAvailable(from candidates: [String]) async -> String? {
        if StorageEnvironment.isRunningTests {
            return candidates.first
        }
        for candidate in candidates {
            if await ProjectIconService.shared.probeIconURL(candidate) {
                return candidate
            }
        }
        return nil
    }

    static func faviconURL(for pageURL: String) -> String? {
        guard let url = URL(string: pageURL),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }

    static func buildCandidateURLs(specIconURL: String?, discoveredFavicons: [String]) -> [String] {
        var seen = Set<String>()
        var candidates: [String] = []

        func append(_ raw: String?) {
            guard let normalized = normalizeCandidate(raw), !seen.contains(normalized) else { return }
            seen.insert(normalized)
            candidates.append(normalized)
        }

        for favicon in discoveredFavicons {
            append(favicon)
        }
        append(specIconURL)
        return candidates
    }

    // MARK: - Private

    private static func websiteOrigins(specIconURL: String?, sourceURL: String?) -> [String] {
        var origins: [String] = []
        var seen = Set<String>()

        func appendOrigin(from urlString: String?) {
            guard let urlString,
                  let origin = originPageURL(for: urlString),
                  !seen.contains(origin) else {
                return
            }
            seen.insert(origin)
            origins.append(origin)
        }

        appendOrigin(from: sourceURL)
        appendOrigin(from: specIconURL)
        return origins
    }

    private static func originPageURL(for urlString: String) -> String? {
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              let host = url.host else {
            return nil
        }
        return "https://\(host)/"
    }

    private static func discoverFavicons(for origin: String) async -> [String] {
        var candidates: [String] = []
        if let html = await fetchHTML(from: origin) {
            candidates.append(contentsOf: faviconCandidatesFromHTML(html, baseURL: origin))
        }
        if let fallback = faviconURL(for: origin) {
            candidates.append(fallback)
        }
        return candidates
    }

    private static func fetchHTML(from pageURL: String) async -> String? {
        guard let url = URL(string: pageURL) else { return nil }
        do {
            let data = try await SafeFetchService.shared.fetch(url: url)
            let capped = data.prefix(256_000)
            return String(data: capped, encoding: .utf8)
                ?? String(data: capped, encoding: .ascii)
        } catch {
            return nil
        }
    }

    static func normalizeCandidate(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "#",
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https" else {
            return nil
        }

        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, !Project.allowedIconExtensions.contains(ext) {
            return nil
        }
        return url.absoluteString
    }
}