//
//  SnippetStringUtils.swift
//  Reqeast
//

import Foundation

enum SnippetStringUtils {

    static func shellEscape(_ string: String) -> String {
        if string.isEmpty { return "''" }
        let escaped = string.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    static func doubleQuoteEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    static func indent(_ text: String, spaces: Int) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    static func formatJsonBody(_ json: String) -> String {
        JsonBeautifier.prettify(json) ?? json
    }

    static func bodyContentDescription(_ body: ResolvedBody) -> String {
        switch body {
        case .none:
            return ""
        case .json(let content):
            return content
        case .raw(let content, _):
            return content
        case .formUrlencoded(let fields):
            return fields.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        case .formData(let fields):
            return fields.map { $0.isFile ? "\($0.name): [file: \($0.fileName)]" : "\($0.name): \($0.value)" }
                .joined(separator: "\n")
        case .binary(let fileName):
            return "[binary: \(fileName)]"
        }
    }
}
