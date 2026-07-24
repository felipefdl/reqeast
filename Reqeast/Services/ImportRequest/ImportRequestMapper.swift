//
//  ImportRequestMapper.swift
//  Reqeast
//

import Foundation

enum ImportRequestMapper {

    static func map(_ imported: ImportedRequestData) -> HttpRequestData {
        var data = HttpRequestData()

        // Method
        data.method = resolveMethod(imported.method)

        // URL and query params
        let (baseUrl, urlParams) = extractQueryParams(from: imported.url)
        data.url = baseUrl
        let allParams = urlParams + imported.queryParams
        data.params = allParams.map { KeyValueEntry(key: $0.name, value: $0.value) }
        data.params.append(KeyValueEntry()) // sentinel

        // Headers (filter out auth and content-type)
        var headers = imported.headers
        let authInfo = extractAuth(from: &headers)
        removeContentType(from: &headers)
        data.headers = headers.map { KeyValueEntry(key: $0.name, value: $0.value) }
        data.headers.append(KeyValueEntry()) // sentinel

        // Auth
        applyAuth(authInfo: authInfo, imported: imported, data: &data)

        // Body
        applyBody(imported: imported, headers: imported.headers, data: &data)

        // Settings
        if let followRedirects = imported.followRedirects {
            data.followRedirects = followRedirects
        }
        if imported.insecure {
            data.sslVerify = false
        }

        return data
    }

    // MARK: - Method

    private static func resolveMethod(_ method: String?) -> HttpMethod {
        guard let method else { return .get }
        switch method.uppercased() {
        case "GET":     return .get
        case "POST":    return .post
        case "PUT":     return .put
        case "PATCH":   return .patch
        case "DELETE":  return .delete
        case "HEAD":    return .head
        case "OPTIONS": return .options
        default:        return .get
        }
    }

    // MARK: - URL + Query Params

    private static func extractQueryParams(from url: String) -> (baseUrl: String, params: [(name: String, value: String)]) {
        // Use URLComponents for proper handling of encoded chars, fragments, etc.
        if let components = URLComponents(string: url) {
            var baseComponents = components
            baseComponents.query = nil
            baseComponents.fragment = nil
            let baseUrl = baseComponents.string ?? url
            let params = (components.queryItems ?? []).map { item in
                (name: item.name, value: item.value ?? "")
            }
            return (baseUrl: baseUrl, params: params)
        }

        // Manual fallback for malformed URLs that URLComponents rejects
        guard let questionIndex = url.firstIndex(of: "?") else {
            return (baseUrl: url, params: [])
        }

        let base = String(url[url.startIndex..<questionIndex])
        let queryString = String(url[url.index(after: questionIndex)...])
        var params: [(name: String, value: String)] = []

        for pair in queryString.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
            let value = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? String(kv[1])) : ""
            params.append((name: key, value: value))
        }

        return (baseUrl: base, params: params)
    }

    // MARK: - Auth

    private struct AuthInfo {
        var type: HttpAuthType = .none
        var token: String = ""
        var username: String = ""
        var password: String = ""
    }

    private static func extractAuth(from headers: inout [(name: String, value: String)]) -> AuthInfo {
        var auth = AuthInfo()

        if let index = headers.firstIndex(where: { $0.name.lowercased() == "authorization" }) {
            let value = headers[index].value
            headers.remove(at: index)

            if value.lowercased().hasPrefix("bearer ") {
                auth.type = .bearer
                auth.token = String(value.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if value.lowercased().hasPrefix("basic ") {
                let encoded = String(value.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if let decoded = Data(base64Encoded: encoded).flatMap({ String(data: $0, encoding: .utf8) }) {
                    let parts = decoded.split(separator: ":", maxSplits: 1)
                    auth.type = .basic
                    auth.username = String(parts[0])
                    auth.password = parts.count > 1 ? String(parts[1]) : ""
                } else {
                    auth.type = .bearer
                    auth.token = value
                }
            }
        }

        return auth
    }

    private static func applyAuth(authInfo: AuthInfo, imported: ImportedRequestData, data: inout HttpRequestData) {
        // Basic auth from -u flag takes priority
        if let user = imported.basicAuthUser {
            data.authType = .basic
            data.authUsername = user
            data.authPassword = imported.basicAuthPassword ?? ""
        } else if authInfo.type != .none {
            data.authType = authInfo.type
            data.authToken = authInfo.token
            data.authUsername = authInfo.username
            data.authPassword = authInfo.password
        }
    }

    // MARK: - Headers

    private static func removeContentType(from headers: inout [(name: String, value: String)]) {
        headers.removeAll { $0.name.lowercased() == "content-type" }
    }

    // MARK: - Body

    private static func applyBody(imported: ImportedRequestData, headers: [(name: String, value: String)], data: inout HttpRequestData) {
        if imported.bodyIsForm && !imported.formFields.isEmpty {
            data.bodyType = .formData
            data.bodyFormData = imported.formFields.map { KeyValueEntry(key: $0.name, value: $0.value) }
            data.bodyFormData.append(KeyValueEntry()) // sentinel
            return
        }

        guard let body = imported.body, !body.isEmpty else { return }

        let contentType = headers
            .first { $0.name.lowercased() == "content-type" }
            .map { $0.value.lowercased() }

        if contentType?.contains("application/json") == true || looksLikeJson(body) {
            data.bodyType = .json
            data.bodyContent = body
        } else if contentType?.contains("application/x-www-form-urlencoded") == true {
            data.bodyType = .urlencoded
            data.bodyFormData = parseUrlEncodedBody(body)
            data.bodyFormData.append(KeyValueEntry()) // sentinel
        } else if contentType?.contains("text/") == true || contentType?.contains("xml") == true {
            data.bodyType = .raw
            data.bodyContent = body
            if let ct = contentType {
                data.rawContentType = inferRawContentType(ct)
            }
        } else {
            // Default: try JSON if it looks like it, otherwise raw
            if looksLikeJson(body) {
                data.bodyType = .json
            } else {
                data.bodyType = .raw
                data.rawContentType = .text
            }
            data.bodyContent = body
        }
    }

    private static func looksLikeJson(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
               (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }

    private static func parseUrlEncodedBody(_ body: String) -> [KeyValueEntry] {
        body.split(separator: "&").map { pair in
            let kv = pair.split(separator: "=", maxSplits: 1)
            let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
            let value = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? String(kv[1])) : ""
            return KeyValueEntry(key: key, value: value)
        }
    }

    private static func inferRawContentType(_ contentType: String) -> HttpRawContentType {
        if contentType.contains("xml") { return .xml }
        if contentType.contains("html") { return .html }
        if contentType.contains("javascript") { return .javascript }
        if contentType.contains("json") { return .json }
        return .text
    }
}
