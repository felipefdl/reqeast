//
//  RustReqwestGenerator.swift
//  Reqeast
//

import Foundation

enum RustReqwestGenerator {
    static func generate(_ request: ResolvedHttpRequest) -> String {
        let e = SnippetStringUtils.doubleQuoteEscape
        let method = request.method.lowercased()

        var lines: [String] = [
            "use reqwest;",
            "",
            "#[tokio::main]",
            "async fn main() -> Result<(), Box<dyn std::error::Error>> {",
            "    let client = reqwest::Client::new();"
        ]

        // Form data needs to be built before the request chain
        let formSetup = formDataSetup(request.body)
        if !formSetup.isEmpty {
            lines.append("")
            lines.append(contentsOf: formSetup)
        }

        lines.append("")
        lines.append("    let response = client")
        lines.append("        .\(method)(\"\(e(request.url))\")")

        for (key, value) in request.headers {
            lines.append("        .header(\"\(e(key))\", \"\(e(value))\")")
        }

        lines.append(contentsOf: bodyChain(request.body))

        if request.timeout > 0 {
            lines.append("        .timeout(std::time::Duration::from_secs(\(request.timeout)))")
        }

        lines.append("        .send()")
        lines.append("        .await?;")
        lines.append("")
        lines.append("    println!(\"{}\", response.text().await?);")
        lines.append("    Ok(())")
        lines.append("}")

        return lines.joined(separator: "\n")
    }

    private static func bodyChain(_ body: ResolvedBody) -> [String] {
        let e = SnippetStringUtils.doubleQuoteEscape
        switch body {
        case .none:
            return []
        case .json(let json):
            let formatted = SnippetStringUtils.formatJsonBody(json)
            if (try? JSONSerialization.jsonObject(with: Data(json.utf8))) != nil {
                return ["        .body(r#\"\(formatted)\"#)"]
            }
            return ["        .body(\"\(e(json))\")"]
        case .raw(let text, _):
            return ["        .body(\"\(e(text))\")"]
        case .formUrlencoded(let pairs):
            var lines = ["        .form(&["]
            for (key, value) in pairs {
                lines.append("            (\"\(e(key))\", \"\(e(value))\"),")
            }
            lines.append("        ])")
            return lines
        case .formData:
            return ["        .multipart(form)"]
        case .binary(let fileName):
            return [
                "        // Load binary file: \(fileName)",
                "        .body(std::fs::read(\"\(e(fileName))\")?)"
            ]
        }
    }

    private static func formDataSetup(_ body: ResolvedBody) -> [String] {
        guard case .formData(let fields) = body else { return [] }
        let e = SnippetStringUtils.doubleQuoteEscape
        var lines = ["    let form = reqwest::multipart::Form::new()"]
        for field in fields {
            if field.isFile {
                lines.append("        // .part(\"\(e(field.name))\", reqwest::multipart::Part::file(\"\(e(field.fileName))\").await?)")
            } else {
                lines.append("        .text(\"\(e(field.name))\", \"\(e(field.value))\")")
            }
        }
        lines[lines.count - 1] += ";"
        return lines
    }
}
