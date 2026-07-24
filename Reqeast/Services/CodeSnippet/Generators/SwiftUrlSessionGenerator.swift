//
//  SwiftUrlSessionGenerator.swift
//  Reqeast
//

import Foundation

enum SwiftUrlSessionGenerator {
    static func generate(_ request: ResolvedHttpRequest) -> String {
        let e = SnippetStringUtils.doubleQuoteEscape
        var lines: [String] = ["import Foundation", ""]
        lines.append("let url = URL(string: \"\(e(request.url))\")!")
        lines.append("var request = URLRequest(url: url)")
        lines.append("request.httpMethod = \"\(request.method)\"")

        for (key, value) in request.headers {
            lines.append("request.setValue(\"\(e(value))\", forHTTPHeaderField: \"\(e(key))\")")
        }

        lines.append(contentsOf: bodyLines(request.body))

        if request.timeout > 0 {
            lines.append("request.timeoutInterval = \(request.timeout)")
        }

        lines.append("")
        lines.append("let (data, response) = try await URLSession.shared.data(for: request)")
        lines.append("print(String(data: data, encoding: .utf8) ?? \"\")")

        return lines.joined(separator: "\n")
    }

    private static func bodyLines(_ body: ResolvedBody) -> [String] {
        let e = SnippetStringUtils.doubleQuoteEscape
        switch body {
        case .none:
            return []
        case .json(let json):
            let formatted = SnippetStringUtils.formatJsonBody(json)
            return [
                "request.httpBody = \"\"\"",
                "\(formatted)",
                "\"\"\".data(using: .utf8)"
            ]
        case .raw(let text, _):
            return ["request.httpBody = \"\(e(text))\".data(using: .utf8)"]
        case .formUrlencoded(let pairs):
            let encoded = pairs.map { "\(e($0.0))=\(e($0.1))" }.joined(separator: "&")
            return ["request.httpBody = \"\(encoded)\".data(using: .utf8)"]
        case .formData(let fields):
            var lines = [
                "",
                "let boundary = \"Boundary-\\(UUID().uuidString)\"",
                "request.setValue(\"multipart/form-data; boundary=\\(boundary)\", forHTTPHeaderField: \"Content-Type\")",
                "var bodyData = Data()"
            ]
            for field in fields {
                if field.isFile {
                    lines.append("// Add file field \"\(e(field.name))\" from \"\(e(field.fileName))\"")
                    lines.append("bodyData.append(\"--\\(boundary)\\r\\nContent-Disposition: form-data; name=\\\"\(e(field.name))\\\"; filename=\\\"\(e(field.fileName))\\\"\\r\\nContent-Type: \(e(field.mimeType))\\r\\n\\r\\n\".data(using: .utf8)!)")
                    lines.append("// bodyData.append(fileData)")
                    lines.append("bodyData.append(\"\\r\\n\".data(using: .utf8)!)")
                } else {
                    lines.append("bodyData.append(\"--\\(boundary)\\r\\nContent-Disposition: form-data; name=\\\"\(e(field.name))\\\"\\r\\n\\r\\n\(e(field.value))\\r\\n\".data(using: .utf8)!)")
                }
            }
            lines.append("bodyData.append(\"--\\(boundary)--\\r\\n\".data(using: .utf8)!)")
            lines.append("request.httpBody = bodyData")
            return lines
        case .binary(let fileName):
            return [
                "// Load binary file: \(fileName)",
                "request.httpBody = try Data(contentsOf: URL(fileURLWithPath: \"\(e(fileName))\"))"
            ]
        }
    }
}
