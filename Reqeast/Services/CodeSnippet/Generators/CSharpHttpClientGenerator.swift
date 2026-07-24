//
//  CSharpHttpClientGenerator.swift
//  Reqeast
//

import Foundation

enum CSharpHttpClientGenerator {
    static func generate(_ request: ResolvedHttpRequest) -> String {
        let e = SnippetStringUtils.doubleQuoteEscape
        var lines: [String] = [
            "using System.Net.Http;",
            "",
            "var client = new HttpClient();",
            ""
        ]

        let httpMethod = csharpMethod(request.method)
        lines.append("var request = new HttpRequestMessage(\(httpMethod), \"\(e(request.url))\");")

        let contentHeaders = Set(["content-type", "content-length", "content-encoding"])
        for (key, value) in request.headers where !contentHeaders.contains(key.lowercased()) {
            lines.append("request.Headers.Add(\"\(e(key))\", \"\(e(value))\");")
        }

        lines.append(contentsOf: bodyLines(request.body))

        if request.timeout > 0 {
            lines.append("client.Timeout = TimeSpan.FromSeconds(\(request.timeout));")
        }

        lines.append("")
        lines.append("var response = await client.SendAsync(request);")
        lines.append("var content = await response.Content.ReadAsStringAsync();")
        lines.append("Console.WriteLine(content);")

        return lines.joined(separator: "\n")
    }

    private static func csharpMethod(_ method: String) -> String {
        switch method {
        case "GET": return "HttpMethod.Get"
        case "POST": return "HttpMethod.Post"
        case "PUT": return "HttpMethod.Put"
        case "DELETE": return "HttpMethod.Delete"
        case "PATCH": return "HttpMethod.Patch"
        case "HEAD": return "HttpMethod.Head"
        case "OPTIONS": return "HttpMethod.Options"
        default: return "new HttpMethod(\"\(method)\")"
        }
    }

    private static func bodyLines(_ body: ResolvedBody) -> [String] {
        let e = SnippetStringUtils.doubleQuoteEscape
        switch body {
        case .none:
            return []
        case .json(let json):
            return [
                "request.Content = new StringContent(\"\(e(json))\", System.Text.Encoding.UTF8, \"application/json\");"
            ]
        case .raw(let text, contentType: let ct):
            return [
                "request.Content = new StringContent(\"\(e(text))\", System.Text.Encoding.UTF8, \"\(e(ct))\");"
            ]
        case .formUrlencoded(let pairs):
            var lines = ["request.Content = new FormUrlEncodedContent(new Dictionary<string, string>", "{"]
            for (index, (key, value)) in pairs.enumerated() {
                let comma = index < pairs.count - 1 ? "," : ""
                lines.append("    { \"\(e(key))\", \"\(e(value))\" }\(comma)")
            }
            lines.append("});")
            return lines
        case .formData(let fields):
            var lines = ["var formData = new MultipartFormDataContent();"]
            for field in fields {
                if field.isFile {
                    lines.append("// formData.Add(new ByteArrayContent(fileBytes), \"\(e(field.name))\", \"\(e(field.fileName))\");")
                } else {
                    lines.append("formData.Add(new StringContent(\"\(e(field.value))\"), \"\(e(field.name))\");")
                }
            }
            lines.append("request.Content = formData;")
            return lines
        case .binary(let fileName):
            return [
                "// Load binary file: \(fileName)",
                "request.Content = new ByteArrayContent(File.ReadAllBytes(\"\(e(fileName))\"));"
            ]
        }
    }
}
