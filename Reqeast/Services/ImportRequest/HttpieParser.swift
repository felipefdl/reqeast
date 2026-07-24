//
//  HttpieParser.swift
//  Reqeast
//

import Foundation

enum HttpieParser {

    static func parse(_ tokens: [String]) throws -> ImportedRequestData {
        var data = ImportedRequestData()
        var positional: [String] = []
        var isFormMode = false
        var index = 1 // skip "http" / "https"
        var jsonFields: [(key: String, value: String, raw: Bool)] = []

        while index < tokens.count {
            let token = tokens[index]

            if token == "--form" || token == "-f" {
                isFormMode = true
            } else if token == "--json" || token == "-j" {
                isFormMode = false
            } else if token == "--auth" || token == "-a" {
                index += 1
                if index < tokens.count {
                    let parts = tokens[index].split(separator: ":", maxSplits: 1)
                    data.basicAuthUser = String(parts[0])
                    data.basicAuthPassword = parts.count > 1 ? String(parts[1]) : ""
                }
            } else if token == "--verify" {
                index += 1
                if index < tokens.count, tokens[index].lowercased() == "no" {
                    data.insecure = true
                }
            } else if token == "--follow" || token == "-F" {
                data.followRedirects = true
            } else if token == "--timeout" {
                index += 1 // skip value
            } else if token == "--print" || token == "-p" || token == "--output" || token == "-o" ||
                      token == "--style" || token == "-s" || token == "--session" {
                index += 1 // skip value
            } else if token.hasPrefix("-") {
                // Ignore unknown flags
            } else {
                positional.append(token)
            }

            index += 1
        }

        // Parse positional args: [METHOD] URL [items...]
        var positionalIndex = 0

        // First positional: METHOD or URL
        if positionalIndex < positional.count {
            let first = positional[positionalIndex]
            if isHttpMethod(first) {
                data.method = first.uppercased()
                positionalIndex += 1
            }
        }

        // Second positional (or first if no method): URL
        if positionalIndex < positional.count {
            data.url = positional[positionalIndex]
            positionalIndex += 1
        }

        // Remaining positional: request items
        while positionalIndex < positional.count {
            let item = positional[positionalIndex]
            positionalIndex += 1

            if let eqeqRange = item.range(of: "==") {
                // key==value -> query param
                let key = String(item[item.startIndex..<eqeqRange.lowerBound])
                let value = String(item[eqeqRange.upperBound...])
                data.queryParams.append((name: key, value: value))
            } else if let colonEqRange = item.range(of: ":=") {
                // key:=value -> JSON raw field
                let key = String(item[item.startIndex..<colonEqRange.lowerBound])
                let value = String(item[colonEqRange.upperBound...])
                jsonFields.append((key: key, value: value, raw: true))
            } else if let colonRange = item.range(of: ":"),
                      item[item.startIndex..<colonRange.lowerBound].allSatisfy({ $0.isLetter || $0 == "-" || $0 == "_" }) {
                // Header:Value -> header (key must be alphanumeric/dash/underscore)
                let key = String(item[item.startIndex..<colonRange.lowerBound])
                let value = String(item[colonRange.upperBound...])
                if !key.isEmpty {
                    data.headers.append((name: key, value: value))
                }
            } else if let eqRange = item.range(of: "=") {
                // key=value -> JSON string field or form field
                let key = String(item[item.startIndex..<eqRange.lowerBound])
                let value = String(item[eqRange.upperBound...])
                if isFormMode {
                    data.formFields.append((name: key, value: value))
                } else {
                    jsonFields.append((key: key, value: value, raw: false))
                }
            }
        }

        // Build JSON body from fields
        if !jsonFields.isEmpty {
            data.body = buildJsonBody(jsonFields)
        }

        // Build form body
        if isFormMode && !data.formFields.isEmpty {
            data.bodyIsForm = true
        }

        // Default method
        if data.method == nil {
            let hasBody = data.body != nil || !data.formFields.isEmpty || !jsonFields.isEmpty
            data.method = hasBody ? "POST" : "GET"
        }

        // Prepend scheme if missing
        if !data.url.isEmpty && !data.url.contains("://") {
            data.url = "http://\(data.url)"
        }

        guard !data.url.isEmpty else {
            throw ImportError.noUrlFound
        }

        return data
    }

    // MARK: - Private

    private static func isHttpMethod(_ token: String) -> Bool {
        let upper = token.uppercased()
        return ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"].contains(upper)
    }

    private static func buildJsonBody(_ fields: [(key: String, value: String, raw: Bool)]) -> String {
        var parts: [String] = []
        for field in fields {
            let escapedKey = field.key.replacingOccurrences(of: "\"", with: "\\\"")
            if field.raw {
                parts.append("\"\(escapedKey)\": \(field.value)")
            } else {
                let escapedValue = field.value.replacingOccurrences(of: "\"", with: "\\\"")
                parts.append("\"\(escapedKey)\": \"\(escapedValue)\"")
            }
        }
        return "{\(parts.joined(separator: ", "))}"
    }
}
