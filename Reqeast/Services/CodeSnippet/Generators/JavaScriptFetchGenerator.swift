//
//  JavaScriptFetchGenerator.swift
//  Reqeast
//

import Foundation

enum JavaScriptFetchGenerator {
    static func generate(_ request: ResolvedHttpRequest) -> String {
        let esc = SnippetStringUtils.doubleQuoteEscape
        var options: [String] = []

        if request.method != "GET" {
            options.append("  method: \"\(request.method)\"")
        }

        if !request.headers.isEmpty {
            var headerLines = ["  headers: {"]
            for (key, value) in request.headers {
                headerLines.append("    \"\(esc(key))\": \"\(esc(value))\",")
            }
            headerLines.append("  }")
            options.append(headerLines.joined(separator: "\n"))
        }

        if let bodySnippet = bodyOption(request.body) {
            options.append(bodySnippet)
        }

        var lines: [String] = []
        if hasFormData(request.body) { lines.append(formDataSetup(request.body)) }

        if options.isEmpty {
            lines.append("const response = await fetch(\"\(esc(request.url))\");")
        } else {
            lines.append("const response = await fetch(\"\(esc(request.url))\", {")
            lines.append(options.joined(separator: ",\n"))
            lines.append("});")
        }

        lines.append("")
        lines.append("const data = await response.json();")
        lines.append("console.log(data);")
        return lines.joined(separator: "\n")
    }

    private static func bodyOption(_ body: ResolvedBody) -> String? {
        let esc = SnippetStringUtils.doubleQuoteEscape
        switch body {
        case .none:
            return nil
        case .json(let json):
            let formatted = SnippetStringUtils.formatJsonBody(json)
            return "  body: JSON.stringify(\(formatted))"
        case .raw(let text, _):
            return "  body: \"\(esc(text))\""
        case .formUrlencoded(let pairs):
            let encoded = pairs.map { "\(esc($0.0))=\(esc($0.1))" }.joined(separator: "&")
            return "  body: new URLSearchParams(\"\(encoded)\")"
        case .formData:
            return "  body: formData"
        case .binary(let fileName):
            return "  body: /* contents of \(fileName) */"
        }
    }

    private static func hasFormData(_ body: ResolvedBody) -> Bool {
        if case .formData = body { return true }
        return false
    }

    private static func formDataSetup(_ body: ResolvedBody) -> String {
        guard case .formData(let fields) = body else { return "" }
        let esc = SnippetStringUtils.doubleQuoteEscape
        var lines = ["const formData = new FormData();"]
        for field in fields {
            if field.isFile {
                lines.append("formData.append(\"\(esc(field.name))\", /* file: \(field.fileName) */);")
            } else {
                lines.append("formData.append(\"\(esc(field.name))\", \"\(esc(field.value))\");")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
