//
//  HttpRawGenerator.swift
//  Reqeast
//

import Foundation

enum HttpRawGenerator {
    static func generate(_ request: ResolvedHttpRequest) -> String {
        let (host, path) = extractHostAndPath(request.url)
        var lines: [String] = []

        lines.append("\(request.method) \(path) HTTP/1.1")
        lines.append("Host: \(host)")

        for (key, value) in request.headers where key.lowercased() != "host" {
            lines.append("\(key): \(value)")
        }

        let bodyText = bodyString(request.body)
        if !bodyText.isEmpty {
            lines.append("")
            lines.append(bodyText)
        }

        return lines.joined(separator: "\r\n")
    }

    private static func extractHostAndPath(_ urlString: String) -> (String, String) {
        guard let url = URL(string: urlString) else {
            return ("localhost", "/")
        }
        let host = url.host() ?? "localhost"
        var path = url.path().isEmpty ? "/" : url.path()
        if let query = url.query {
            path += "?\(query)"
        }
        return (host, path)
    }

    private static func bodyString(_ body: ResolvedBody) -> String {
        switch body {
        case .none:
            return ""
        case .json(let json):
            return SnippetStringUtils.formatJsonBody(json)
        case .raw(let text, _):
            return text
        case .formUrlencoded(let pairs):
            return pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        case .formData(let fields):
            let boundary = "----FormBoundary"
            var parts: [String] = []
            for field in fields {
                parts.append("--\(boundary)")
                if field.isFile {
                    parts.append("Content-Disposition: form-data; name=\"\(field.name)\"; filename=\"\(field.fileName)\"")
                    parts.append("Content-Type: \(field.mimeType)")
                    parts.append("")
                    parts.append("(binary)")
                } else {
                    parts.append("Content-Disposition: form-data; name=\"\(field.name)\"")
                    parts.append("")
                    parts.append(field.value)
                }
            }
            parts.append("--\(boundary)--")
            return parts.joined(separator: "\r\n")
        case .binary(let fileName):
            return "(contents of \(fileName))"
        }
    }
}
