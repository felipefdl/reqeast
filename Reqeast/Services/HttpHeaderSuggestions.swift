//
//  HttpHeaderSuggestions.swift
//  Reqeast
//

import Foundation

enum HttpHeaderSuggestions {
    struct HeaderDefinition {
        let name: String
        let description: String
    }

    static let allHeaders: [HeaderDefinition] = [
        // Content negotiation
        HeaderDefinition(name: "Accept", description: "Acceptable response media types"),
        HeaderDefinition(name: "Accept-Charset", description: "Acceptable character sets"),
        HeaderDefinition(name: "Accept-Encoding", description: "Acceptable content encodings"),
        HeaderDefinition(name: "Accept-Language", description: "Preferred languages for response"),
        // Authentication
        HeaderDefinition(name: "Authorization", description: "Authentication credentials"),
        HeaderDefinition(name: "Proxy-Authorization", description: "Proxy authentication credentials"),
        HeaderDefinition(name: "X-API-Key", description: "API key for authentication"),
        // Caching
        HeaderDefinition(name: "Cache-Control", description: "Caching directives"),
        HeaderDefinition(name: "If-Match", description: "Conditional request by ETag match"),
        HeaderDefinition(name: "If-Modified-Since", description: "Conditional request by date"),
        HeaderDefinition(name: "If-None-Match", description: "Conditional request by ETag mismatch"),
        HeaderDefinition(name: "If-Range", description: "Conditional range request"),
        HeaderDefinition(name: "If-Unmodified-Since", description: "Conditional request by unmodified date"),
        HeaderDefinition(name: "Pragma", description: "Legacy HTTP/1.0 cache directive"),
        // Content metadata
        HeaderDefinition(name: "Content-Disposition", description: "Content presentation type"),
        HeaderDefinition(name: "Content-Encoding", description: "Content compression encoding"),
        HeaderDefinition(name: "Content-Language", description: "Content natural language"),
        HeaderDefinition(name: "Content-Length", description: "Size of the request body in bytes"),
        HeaderDefinition(name: "Content-Type", description: "Media type of the request body"),
        // Connection
        HeaderDefinition(name: "Connection", description: "Connection management options"),
        HeaderDefinition(name: "Upgrade", description: "Protocol upgrade request"),
        HeaderDefinition(name: "TE", description: "Acceptable transfer encodings"),
        HeaderDefinition(name: "Max-Forwards", description: "Maximum number of proxy hops"),
        // Context
        HeaderDefinition(name: "Host", description: "Target host and port"),
        HeaderDefinition(name: "Origin", description: "Request origin for CORS"),
        HeaderDefinition(name: "Referer", description: "URL of the referring page"),
        HeaderDefinition(name: "User-Agent", description: "Client software identifier"),
        HeaderDefinition(name: "From", description: "Email address of the requester"),
        HeaderDefinition(name: "Date", description: "Date and time of the request"),
        HeaderDefinition(name: "Cookie", description: "Previously stored cookies"),
        HeaderDefinition(name: "DNT", description: "Do Not Track preference"),
        HeaderDefinition(name: "Expect", description: "Expected server behavior"),
        // Security
        HeaderDefinition(name: "Sec-Fetch-Dest", description: "Fetch destination type"),
        HeaderDefinition(name: "Sec-Fetch-Mode", description: "Fetch request mode"),
        HeaderDefinition(name: "Sec-Fetch-Site", description: "Fetch origin relationship"),
        // Proxy
        HeaderDefinition(name: "Forwarded", description: "Proxy forwarding information"),
        HeaderDefinition(name: "Via", description: "Intermediate proxy identifiers"),
        HeaderDefinition(name: "X-Forwarded-For", description: "Original client IP address"),
        HeaderDefinition(name: "X-Forwarded-Host", description: "Original host requested"),
        HeaderDefinition(name: "X-Forwarded-Proto", description: "Original request protocol"),
        // Tracing
        HeaderDefinition(name: "X-Request-ID", description: "Unique request identifier"),
        HeaderDefinition(name: "X-Correlation-ID", description: "Distributed tracing identifier"),
        HeaderDefinition(name: "Range", description: "Requested byte range of resource"),
    ]

    static let headerValues: [String: [String]] = [
        "Content-Type": [
            "application/json",
            "application/json; charset=utf-8",
            "application/xml",
            "application/x-www-form-urlencoded",
            "application/octet-stream",
            "application/pdf",
            "application/javascript",
            "text/plain",
            "text/html",
            "text/css",
            "text/csv",
            "text/xml",
            "multipart/form-data",
            "image/png",
            "image/jpeg",
        ],
        "Accept": [
            "application/json",
            "application/xml",
            "application/octet-stream",
            "text/plain",
            "text/html",
            "text/csv",
            "text/xml",
            "image/png",
            "image/jpeg",
            "image/*",
            "*/*",
        ],
        "Accept-Encoding": [
            "gzip",
            "deflate",
            "br",
            "gzip, deflate, br",
            "identity",
        ],
        "Accept-Language": [
            "en",
            "en-US",
            "en-GB",
            "es",
            "fr",
            "de",
            "ja",
            "zh-CN",
            "pt-BR",
        ],
        "Authorization": [
            "Bearer ",
            "Basic ",
            "Token ",
            "ApiKey ",
        ],
        "Cache-Control": [
            "no-cache",
            "no-store",
            "no-transform",
            "max-age=0",
            "max-age=3600",
            "max-stale",
            "only-if-cached",
            "no-cache, no-store",
        ],
        "Connection": [
            "keep-alive",
            "close",
            "upgrade",
        ],
        "DNT": [
            "0",
            "1",
        ],
        "Expect": [
            "100-continue",
        ],
    ]

    static func isKnownHeader(_ name: String) -> Bool {
        allHeaders.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func filterHeaders(matching query: String) -> [HeaderDefinition] {
        if query.isEmpty { return [] }
        if allHeaders.contains(where: { $0.name.caseInsensitiveCompare(query) == .orderedSame }) { return [] }
        let lowered = query.lowercased()
        return allHeaders.filter { $0.name.lowercased().contains(lowered) }
    }

    static func filterValues(forHeader header: String, matching query: String) -> [String] {
        let normalizedHeader = allHeaders.first { $0.name.caseInsensitiveCompare(header) == .orderedSame }?.name ?? header
        guard let values = headerValues[normalizedHeader] else { return [] }
        if query.isEmpty { return values }
        if values.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) { return [] }
        let lowered = query.lowercased()
        return values.filter { $0.lowercased().contains(lowered) }
    }
}
