//
//  PythonRequestsGenerator.swift
//  Reqeast
//

import Foundation

enum PythonRequestsGenerator {
    static func generate(_ request: ResolvedHttpRequest) -> String {
        let method = request.method.lowercased()
        let esc = SnippetStringUtils.doubleQuoteEscape
        var lines: [String] = ["import requests", ""]
        lines.append("url = \"\(esc(request.url))\"")

        if !request.headers.isEmpty {
            lines.append("headers = {")
            for (key, value) in request.headers {
                lines.append("    \"\(esc(key))\": \"\(esc(value))\",")
            }
            lines.append("}")
        }

        let bodyArg = appendBody(request.body, lines: &lines)
        lines.append("")

        var callParts = ["url"]
        if !request.headers.isEmpty { callParts.append("headers=headers") }
        if let arg = bodyArg { callParts.append(arg) }
        callParts.append("timeout=\(request.timeout)")

        lines.append("response = requests.\(method)(\(callParts.joined(separator: ", ")))")
        lines.append("print(response.status_code)")
        lines.append("print(response.text)")

        return lines.joined(separator: "\n")
    }

    private static func appendBody(_ body: ResolvedBody, lines: inout [String]) -> String? {
        let esc = SnippetStringUtils.doubleQuoteEscape
        switch body {
        case .none:
            return nil
        case .json(let json):
            let formatted = SnippetStringUtils.formatJsonBody(json)
            lines.append("payload = \"\(esc(formatted))\"")
            return "data=payload"
        case .raw(let text, _):
            lines.append("payload = \"\(esc(text))\"")
            return "data=payload"
        case .formUrlencoded(let pairs):
            lines.append("payload = {")
            for (key, value) in pairs {
                lines.append("    \"\(esc(key))\": \"\(esc(value))\",")
            }
            lines.append("}")
            return "data=payload"
        case .formData(let fields):
            lines.append("files = {")
            for field in fields {
                if field.isFile {
                    lines.append("    \"\(esc(field.name))\": (\"\(esc(field.fileName))\", open(\"\(esc(field.fileName))\", \"rb\"), \"\(esc(field.mimeType))\"),")
                } else {
                    lines.append("    \"\(esc(field.name))\": (None, \"\(esc(field.value))\"),")
                }
            }
            lines.append("}")
            return "files=files"
        case .binary(let fileName):
            lines.append("payload = open(\"\(esc(fileName))\", \"rb\")")
            return "data=payload"
        }
    }
}
