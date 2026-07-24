//
//  ProjectIconResolver+FaviconHTML.swift
//  Reqeast
//

import Foundation

extension ProjectIconResolver {

    /// Parses `<link rel="…icon…">` tags from HTML and returns HTTPS candidates smallest-first.
    static func faviconCandidatesFromHTML(_ html: String, baseURL: String) -> [String] {
        guard let base = URL(string: baseURL) else { return [] }

        var ranked: [(priority: Int, url: String)] = []
        var seen = Set<String>()

        for tag in linkTags(in: html) {
            guard isIconRel(tag["rel"]), let href = tag["href"], !href.isEmpty else { continue }
            guard let absolute = resolveHTTPSURL(href, relativeTo: base),
                  let normalized = normalizeCandidate(absolute),
                  !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            ranked.append((
                iconPriority(rel: tag["rel"] ?? "", sizes: tag["sizes"], href: href),
                normalized
            ))
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.url < rhs.url
            }
            .map(\.url)
    }

    // MARK: - HTML parsing

    private static func linkTags(in html: String) -> [[String: String]] {
        guard let regex = try? NSRegularExpression(pattern: #"<link\s+([^>]+)>"#, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: 1), in: html) else { return nil }
            return parseAttributes(String(html[captureRange]))
        }
    }

    private static func parseAttributes(_ fragment: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#,
            options: [.caseInsensitive]
        ) else {
            return [:]
        }

        var attributes: [String: String] = [:]
        let range = NSRange(fragment.startIndex..<fragment.endIndex, in: fragment)
        for match in regex.matches(in: fragment, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: fragment) else { continue }
            let name = String(fragment[nameRange]).lowercased()
            var value: String?
            for index in 2...4 where value == nil {
                guard match.range(at: index).location != NSNotFound,
                      let valueRange = Range(match.range(at: index), in: fragment) else {
                    continue
                }
                value = String(fragment[valueRange])
            }
            if let value {
                attributes[name] = value
            }
        }
        return attributes
    }

    private static func isIconRel(_ rel: String?) -> Bool {
        guard let rel else { return false }
        let tokens = rel.lowercased().split { $0.isWhitespace || $0 == "/" }
        return tokens.contains("icon") || (tokens.contains("shortcut") && tokens.contains("icon"))
    }

    private static func iconPriority(rel: String, sizes: String?, href: String) -> Int {
        let relLower = rel.lowercased()
        if relLower.contains("apple-touch") {
            return 1_000
        }

        if let sizes, let dimension = smallestDeclaredSize(sizes) {
            return dimension
        }

        let ext = URL(string: href)?.pathExtension.lowercased() ?? ""
        switch ext {
        case "ico": return 48
        case "png": return 64
        case "svg": return 96
        case "webp": return 112
        default: return 128
        }
    }

    private static func smallestDeclaredSize(_ sizes: String) -> Int? {
        let pattern = #"(\d+)\s*x\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(sizes.startIndex..<sizes.endIndex, in: sizes)
        let dimensions = regex.matches(in: sizes, range: range).compactMap { match -> Int? in
            guard let widthRange = Range(match.range(at: 1), in: sizes),
                  let heightRange = Range(match.range(at: 2), in: sizes),
                  let width = Int(sizes[widthRange]),
                  let height = Int(sizes[heightRange]) else {
                return nil
            }
            return max(width, height)
        }
        return dimensions.min()
    }

    static func resolveHTTPSURL(_ href: String, relativeTo base: URL) -> String? {
        guard let url = URL(string: href, relativeTo: base)?.absoluteURL,
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url.absoluteString
    }
}