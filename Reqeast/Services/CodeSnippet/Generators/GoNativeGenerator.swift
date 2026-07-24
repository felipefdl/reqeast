//
//  GoNativeGenerator.swift
//  Reqeast
//

import Foundation

enum GoNativeGenerator {
    static func generate(_ request: ResolvedHttpRequest) -> String {
        let e = SnippetStringUtils.doubleQuoteEscape
        var imports = ["\"fmt\"", "\"io\"", "\"net/http\""]
        let bodySetup = bodyLines(request.body)

        if bodySetup.needsStrings { imports.append("\"strings\"") }
        if bodySetup.needsUrl { imports.append("\"net/url\"") }
        if bodySetup.needsBytes { imports.append("\"bytes\""); imports.append("\"mime/multipart\"") }
        if request.timeout > 0 { imports.append("\"time\"") }

        imports.sort()
        var lines: [String] = ["package main", "", "import ("]
        for imp in imports { lines.append("    \(imp)") }
        lines.append(")")
        lines.append("")
        lines.append("func main() {")

        lines.append(contentsOf: bodySetup.lines.map { "    \($0)" })

        let bodyVar = bodySetup.varName
        lines.append("    req, err := http.NewRequest(\"\(request.method)\", \"\(e(request.url))\", \(bodyVar))")
        lines.append("    if err != nil {")
        lines.append("        panic(err)")
        lines.append("    }")

        for (key, value) in request.headers {
            lines.append("    req.Header.Set(\"\(e(key))\", \"\(e(value))\")")
        }

        lines.append("")
        if request.timeout > 0 {
            lines.append("    client := &http.Client{Timeout: \(request.timeout) * time.Second}")
        } else {
            lines.append("    client := &http.Client{}")
        }
        lines.append("    resp, err := client.Do(req)")
        lines.append("    if err != nil {")
        lines.append("        panic(err)")
        lines.append("    }")
        lines.append("    defer resp.Body.Close()")
        lines.append("")
        lines.append("    respBody, _ := io.ReadAll(resp.Body)")
        lines.append("    fmt.Println(string(respBody))")
        lines.append("}")

        return lines.joined(separator: "\n")
    }

    private typealias Setup = (lines: [String], varName: String, needsStrings: Bool, needsUrl: Bool, needsBytes: Bool)

    private static func bodyLines(_ body: ResolvedBody) -> Setup {
        let e = SnippetStringUtils.doubleQuoteEscape
        switch body {
        case .none:
            return ([], "nil", false, false, false)
        case .json(let json):
            return (["body := strings.NewReader(`\(SnippetStringUtils.formatJsonBody(json))`)"], "body", true, false, false)
        case .raw(let text, _):
            return (["body := strings.NewReader(\"\(e(text))\")"], "body", true, false, false)
        case .formUrlencoded(let pairs):
            var lines = ["data := url.Values{}"]
            for (key, value) in pairs { lines.append("data.Set(\"\(e(key))\", \"\(e(value))\")") }
            lines.append("body := strings.NewReader(data.Encode())")
            return (lines, "body", true, true, false)
        case .formData(let fields):
            var lines = ["body := &bytes.Buffer{}", "writer := multipart.NewWriter(body)"]
            for field in fields {
                if field.isFile {
                    lines.append("// Add file \"\(e(field.name))\" from \"\(e(field.fileName))\"")
                } else {
                    lines.append("writer.WriteField(\"\(e(field.name))\", \"\(e(field.value))\")")
                }
            }
            lines.append("writer.Close()")
            return (lines, "body", false, false, true)
        case .binary(let fileName):
            return (["// Load binary file: \(fileName)", "body := bytes.NewReader(fileBytes)"], "body", false, false, true)
        }
    }
}
