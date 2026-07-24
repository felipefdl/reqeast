//
//  JavaOkHttpGenerator.swift
//  Reqeast
//

import Foundation

enum JavaOkHttpGenerator {
    static func generate(_ request: ResolvedHttpRequest) -> String {
        let e = SnippetStringUtils.doubleQuoteEscape
        let method = request.method.lowercased()
        var lines: [String] = [
            "import okhttp3.*;",
            "",
            "public class Main {",
            "    public static void main(String[] args) throws Exception {",
            "        OkHttpClient client = new OkHttpClient();"
        ]

        lines.append(contentsOf: bodyDeclaration(request.body).map { "        \($0)" })

        lines.append("")
        lines.append("        Request request = new Request.Builder()")
        lines.append("            .url(\"\(e(request.url))\")")

        let bodyVar = hasBody(request.body) ? "body" : nil
        lines.append("            .\(methodCall(method, bodyVar: bodyVar))")

        for (key, value) in request.headers {
            lines.append("            .addHeader(\"\(e(key))\", \"\(e(value))\")")
        }

        lines.append("            .build();")
        lines.append("")
        lines.append("        Response response = client.newCall(request).execute();")
        lines.append("        System.out.println(response.body().string());")
        lines.append("    }")
        lines.append("}")

        return lines.joined(separator: "\n")
    }

    private static func methodCall(_ method: String, bodyVar: String?) -> String {
        switch method {
        case "get": return "get()"
        case "head": return "head()"
        case "delete" where bodyVar == nil: return "delete()"
        default: return "\(method)(\(bodyVar ?? "RequestBody.create(null, \"\")"))"
        }
    }

    private static func hasBody(_ body: ResolvedBody) -> Bool {
        if case .none = body { return false }
        return true
    }

    private static func bodyDeclaration(_ body: ResolvedBody) -> [String] {
        let e = SnippetStringUtils.doubleQuoteEscape
        switch body {
        case .none: return []
        case .json(let json):
            return ["", "MediaType mediaType = MediaType.parse(\"application/json\");",
                    "RequestBody body = RequestBody.create(mediaType, \"\(e(json))\");"]
        case .raw(let text, contentType: let ct):
            return ["", "MediaType mediaType = MediaType.parse(\"\(e(ct))\");",
                    "RequestBody body = RequestBody.create(mediaType, \"\(e(text))\");"]
        case .formUrlencoded(let pairs):
            var lines = ["", "RequestBody body = new FormBody.Builder()"]
            for (key, value) in pairs { lines.append("    .add(\"\(e(key))\", \"\(e(value))\")") }
            lines.append("    .build();")
            return lines
        case .formData(let fields):
            var lines = ["", "RequestBody body = new MultipartBody.Builder()", "    .setType(MultipartBody.FORM)"]
            for field in fields {
                if field.isFile { lines.append("    // .addFormDataPart(\"\(e(field.name))\", \"\(e(field.fileName))\", fileBody)") }
                else { lines.append("    .addFormDataPart(\"\(e(field.name))\", \"\(e(field.value))\")") }
            }
            lines.append("    .build();")
            return lines
        case .binary(let fileName):
            return ["", "// Load binary file: \(fileName)",
                    "RequestBody body = RequestBody.create(MediaType.parse(\"application/octet-stream\"), new java.io.File(\"\(e(fileName))\"));"]
        }
    }
}
