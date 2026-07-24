//
//  CurlGenerator.swift
//  Reqeast
//

import Foundation

enum CurlGenerator {
    static func generate(_ request: ResolvedHttpRequest) -> String {
        var parts: [String] = ["curl"]

        if request.method != "GET" {
            parts.append("-X \(request.method)")
        }

        parts.append(SnippetStringUtils.shellEscape(request.url))

        for (key, value) in request.headers {
            parts.append("-H \(SnippetStringUtils.shellEscape("\(key): \(value)"))")
        }

        parts.append(contentsOf: bodyParts(request.body))

        return parts.joined(separator: " \\\n  ")
    }

    private static func bodyParts(_ body: ResolvedBody) -> [String] {
        switch body {
        case .none:
            return []
        case .json(let json):
            let formatted = SnippetStringUtils.formatJsonBody(json)
            return ["-d \(SnippetStringUtils.shellEscape(formatted))"]
        case .raw(let text, _):
            return ["-d \(SnippetStringUtils.shellEscape(text))"]
        case .formUrlencoded(let pairs):
            return pairs.map { key, value in
                "--data-urlencode \(SnippetStringUtils.shellEscape("\(key)=\(value)"))"
            }
        case .formData(let fields):
            return fields.map { field in
                if field.isFile {
                    return "-F \(SnippetStringUtils.shellEscape("\(field.name)=@\(field.fileName);type=\(field.mimeType)"))"
                }
                return "-F \(SnippetStringUtils.shellEscape("\(field.name)=\(field.value)"))"
            }
        case .binary(let fileName):
            return ["--data-binary \(SnippetStringUtils.shellEscape("@\(fileName)"))"]
        }
    }
}
