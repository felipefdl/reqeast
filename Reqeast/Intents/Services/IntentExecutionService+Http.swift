//
//  IntentExecutionService+Http.swift
//  Reqeast
//

import Foundation

extension IntentExecutionService {

    static func executeHttp(request: Request, environment: ApiEnvironment?, timeout: Int) async throws -> String {
        guard let data = request.httpData else {
            throw IntentExecutionError.executionFailed("Missing HTTP configuration")
        }

        let sub: (String) -> String = { EnvironmentVariableService.substitute($0, environment: environment) }

        let url = UrlNormalizer.normalize(sub(data.url))
        let headers = data.headers.filter { $0.enabled && !$0.key.isEmpty }
            .map { KeyValueEntry(key: sub($0.key), value: sub($0.value)) }
        let params = data.params.filter { $0.enabled && !$0.key.isEmpty }
            .map { KeyValueEntry(key: sub($0.key), value: sub($0.value)) }
        let bodyContent = sub(data.bodyContent)
        let bodyFormData = data.bodyFormData.filter { $0.enabled && !$0.key.isEmpty }
            .map { KeyValueEntry(key: sub($0.key), value: sub($0.value)) }
        let authToken = sub(data.authToken)
        let authUsername = sub(data.authUsername)
        let authPassword = sub(data.authPassword)
        let authApiKeyName = sub(data.authApiKeyName)
        let authApiKeyValue = sub(data.authApiKeyValue)

        var mergedHeaders = headers

        switch data.authType {
        case .bearer:
            if !authToken.isEmpty {
                mergedHeaders.append(KeyValueEntry(key: "Authorization", value: "Bearer \(authToken)"))
            }
        case .basic:
            if !authUsername.isEmpty {
                let credentials = "\(authUsername):\(authPassword)"
                if let encoded = credentials.data(using: .utf8)?.base64EncodedString() {
                    mergedHeaders.append(KeyValueEntry(key: "Authorization", value: "Basic \(encoded)"))
                }
            }
        case .apiKey:
            if !authApiKeyName.isEmpty && data.authApiKeyLocation == "header" {
                mergedHeaders.append(KeyValueEntry(key: authApiKeyName, value: authApiKeyValue))
            }
        default:
            break
        }

        var finalUrl = url
        let enabledParams = params.filter { !$0.key.isEmpty }
        if !enabledParams.isEmpty {
            let queryString = enabledParams.map { entry in
                let key = entry.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? entry.key
                let value = entry.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? entry.value
                return "\(key)=\(value)"
            }.joined(separator: "&")
            let separator = finalUrl.contains("?") ? "&" : "?"
            finalUrl += "\(separator)\(queryString)"
        }

        if data.authType == .apiKey && data.authApiKeyLocation == "query" && !authApiKeyName.isEmpty {
            let separator = finalUrl.contains("?") ? "&" : "?"
            finalUrl += "\(separator)\(authApiKeyName)=\(authApiKeyValue)"
        }

        let rustHeaders = mergedHeaders.map { KeyValuePair(key: $0.key, value: $0.value, enabled: true) }

        let rustBody: HttpBody
        switch data.bodyType {
        case .json:
            rustBody = .json(content: bodyContent)
        case .urlencoded:
            let fields = bodyFormData.map { KeyValuePair(key: $0.key, value: $0.value, enabled: true) }
            rustBody = .formUrlencoded(fields: fields)
        case .raw:
            rustBody = .raw(content: bodyContent, contentType: data.rawContentType?.mimeType ?? "text/plain")
        case .formData:
            let fields = data.bodyFormDataEntries
                .filter { $0.enabled && !$0.key.isEmpty && $0.fieldType == .text }
                .map { entry in
                    MultipartField(
                        name: sub(entry.key),
                        value: Data(sub(entry.value).utf8),
                        fileName: nil,
                        contentType: nil,
                        isFile: false
                    )
                }
            rustBody = .multipart(fields: fields)
        case .binary, .none:
            rustBody = .none
        }

        let rustHttpVersion: HttpVersion = switch data.httpVersion {
        case "http1": .http1
        case "http2": .http2
        default: .auto
        }

        let config = HttpRequestConfig(
            url: finalUrl,
            method: data.method,
            headers: rustHeaders,
            body: rustBody,
            timeoutSecs: UInt32(timeout),
            followRedirects: data.followRedirects,
            maxRedirects: UInt32(data.maxRedirects),
            sslVerify: data.sslVerify,
            httpVersion: rustHttpVersion,
            encodeUrl: data.encodeUrl,
            followOriginalMethod: data.followOriginalMethod,
            followAuthHeader: data.followAuthHeader,
            removeRefererOnRedirect: data.removeRefererOnRedirect,
            cookies: []
        )

        let client = try HttpClient()
        return try await intentWithTimeout(seconds: timeout) {
            let response = try await Task.detached { try client.send(config: config) }.value
            let body = Data(response.body)
            return String(data: body, encoding: .utf8) ?? body.base64EncodedString()
        }
    }
}
