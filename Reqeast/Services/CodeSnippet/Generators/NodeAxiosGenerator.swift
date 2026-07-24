//
//  NodeAxiosGenerator.swift
//  Reqeast
//

import Foundation

enum NodeAxiosGenerator {
    static func generate(_ request: ResolvedHttpRequest) -> String {
        let esc = SnippetStringUtils.doubleQuoteEscape
        let method = request.method.lowercased()
        let timeoutMs = request.timeout * 1000

        var lines: [String] = [
            "const axios = require(\"axios\");",
            "",
        ]

        if hasFormData(request.body) { lines.append(contentsOf: formDataSetup(request.body)) }

        var configLines: [String] = []
        configLines.append("  method: \"\(method)\"")
        configLines.append("  url: \"\(esc(request.url))\"")

        if !request.headers.isEmpty {
            var headerBlock = ["  headers: {"]
            for (key, value) in request.headers {
                headerBlock.append("    \"\(esc(key))\": \"\(esc(value))\",")
            }
            headerBlock.append("  }")
            configLines.append(headerBlock.joined(separator: "\n"))
        }

        if let dataSnippet = dataOption(request.body) {
            configLines.append(dataSnippet)
        }

        configLines.append("  timeout: \(timeoutMs)")

        lines.append("const response = await axios({")
        lines.append(configLines.joined(separator: ",\n"))
        lines.append("});")
        lines.append("")
        lines.append("console.log(response.data);")

        return lines.joined(separator: "\n")
    }

    private static func dataOption(_ body: ResolvedBody) -> String? {
        let esc = SnippetStringUtils.doubleQuoteEscape
        switch body {
        case .none:
            return nil
        case .json(let json):
            let formatted = SnippetStringUtils.formatJsonBody(json)
            return "  data: \(formatted)"
        case .raw(let text, _):
            return "  data: \"\(esc(text))\""
        case .formUrlencoded(let pairs):
            let encoded = pairs.map { "\(esc($0.0))=\(esc($0.1))" }.joined(separator: "&")
            return "  data: \"\(encoded)\""
        case .formData:
            return "  data: formData"
        case .binary(let fileName):
            return "  data: /* contents of \(fileName) */"
        }
    }

    private static func hasFormData(_ body: ResolvedBody) -> Bool {
        if case .formData = body { return true }
        return false
    }

    private static func formDataSetup(_ body: ResolvedBody) -> [String] {
        guard case .formData(let fields) = body else { return [] }
        let esc = SnippetStringUtils.doubleQuoteEscape
        var lines = ["const FormData = require(\"form-data\");", "const formData = new FormData();"]
        for field in fields {
            if field.isFile {
                lines.append("formData.append(\"\(esc(field.name))\", /* file: \(field.fileName) */);")
            } else {
                lines.append("formData.append(\"\(esc(field.name))\", \"\(esc(field.value))\");")
            }
        }
        lines.append("")
        return lines
    }
}
