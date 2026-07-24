//
//  HttpRequestResolver.swift
//  Reqeast
//

import Foundation

enum HttpRequestResolver {

    static func resolve(
        _ data: HttpRequestData,
        environment: ApiEnvironment?
    ) -> ResolvedHttpRequest {
        let sub = { (input: String) in
            EnvironmentVariableService.substitute(input, environment: environment)
        }

        let resolvedUrl = sub(data.url)
        var mergedHeaders = resolveAuthHeaders(data: data, url: resolvedUrl, sub: sub)

        // User-defined headers
        let userHeaders = data.headers
            .filter { $0.enabled && !$0.key.isEmpty }
            .map { (sub($0.key), sub($0.value)) }
        mergedHeaders.append(contentsOf: userHeaders)

        // Build URL with query params
        var finalUrl = resolvedUrl
        let enabledParams = data.params.filter { $0.enabled && !$0.key.isEmpty }
        if !enabledParams.isEmpty {
            let queryString = enabledParams.map { entry in
                let key = sub(entry.key).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sub(entry.key)
                let value = sub(entry.value).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sub(entry.value)
                return "\(key)=\(value)"
            }.joined(separator: "&")
            let separator = finalUrl.contains("?") ? "&" : "?"
            finalUrl += "\(separator)\(queryString)"
        }

        // API Key in query
        if data.authType == .apiKey && data.authApiKeyLocation == "query" && !data.authApiKeyName.isEmpty {
            let separator = finalUrl.contains("?") ? "&" : "?"
            finalUrl += "\(separator)\(sub(data.authApiKeyName))=\(sub(data.authApiKeyValue))"
        }

        // Auto-headers (user headers override; respect disabled auto-headers)
        let autoHeaders = AutoHeaderService.generateHeaders(from: data)
            .filter { !data.disabledAutoHeaders.contains($0.key) }
            .map { ($0.key, $0.value) }
        let userHeaderKeys = Set(mergedHeaders.map { $0.0.lowercased() })
        let filteredAutoHeaders = autoHeaders.filter { !userHeaderKeys.contains($0.0.lowercased()) }
        mergedHeaders.append(contentsOf: filteredAutoHeaders)

        let body = resolveBody(data: data, sub: sub)

        return ResolvedHttpRequest(
            method: data.method.rawLabel,
            url: finalUrl,
            headers: mergedHeaders,
            body: body,
            timeout: data.timeoutSeconds
        )
    }

    // MARK: - Auth

    private static func resolveAuthHeaders(
        data: HttpRequestData,
        url: String,
        sub: (String) -> String
    ) -> [(String, String)] {
        var headers: [(String, String)] = []

        switch data.authType {
        case .bearer:
            let token = sub(data.authToken)
            if !token.isEmpty {
                headers.append(("Authorization", "Bearer \(token)"))
            }
        case .basic:
            let username = sub(data.authUsername)
            if !username.isEmpty {
                let credentials = "\(username):\(sub(data.authPassword))"
                if let encoded = credentials.data(using: .utf8)?.base64EncodedString() {
                    headers.append(("Authorization", "Basic \(encoded)"))
                }
            }
        case .apiKey:
            let name = sub(data.authApiKeyName)
            if !name.isEmpty && data.authApiKeyLocation == "header" {
                headers.append((name, sub(data.authApiKeyValue)))
            }
        case .jwtBearer:
            if let ad = data.authData {
                if let token = JwtAuthService.generateToken(
                    algorithm: ad.jwtAlgorithm,
                    secret: sub(ad.jwtSecret),
                    payload: sub(ad.jwtPayload),
                    base64Encoded: ad.jwtBase64Encoded
                ) {
                    let prefix = ad.jwtHeaderPrefix.isEmpty ? "Bearer" : ad.jwtHeaderPrefix
                    headers.append(("Authorization", "\(prefix) \(token)"))
                }
            }
        case .hawkAuth:
            if let ad = data.authData {
                if let header = HawkAuthService.generateHeader(
                    url: url,
                    method: data.method.rawLabel,
                    authId: sub(ad.hawkAuthId),
                    authKey: sub(ad.hawkAuthKey),
                    algorithm: ad.hawkAlgorithm
                ) {
                    headers.append(("Authorization", header))
                }
            }
        case .awsSignature:
            if let ad = data.authData {
                if let awsHeaders = AwsSignatureService.generateHeaders(
                    url: url,
                    method: data.method.rawLabel,
                    headers: [],
                    body: data.bodyContent.data(using: .utf8),
                    accessKey: sub(ad.awsAccessKey),
                    secretKey: sub(ad.awsSecretKey),
                    region: sub(ad.awsRegion),
                    service: sub(ad.awsService),
                    sessionToken: sub(ad.awsSessionToken)
                ) {
                    headers.append(contentsOf: awsHeaders)
                }
            }
        case .akamaiEdgeGrid:
            if let ad = data.authData {
                if let header = AkamaiEdgeGridService.generateHeader(
                    url: url,
                    method: data.method.rawLabel,
                    body: data.bodyContent.data(using: .utf8),
                    clientToken: sub(ad.akamaiClientToken),
                    clientSecret: sub(ad.akamaiClientSecret),
                    accessToken: sub(ad.akamaiAccessToken)
                ) {
                    headers.append(("Authorization", header))
                }
            }
        case .none, .digestAuth, .oauth1, .oauth2, .ntlm:
            break
        }

        return headers
    }

    // MARK: - Body

    private static func resolveBody(
        data: HttpRequestData,
        sub: (String) -> String
    ) -> ResolvedBody {
        switch data.bodyType {
        case .none:
            return .none
        case .json:
            return .json(sub(data.bodyContent))
        case .raw:
            let contentType = data.rawContentType?.mimeType ?? "text/plain"
            return .raw(sub(data.bodyContent), contentType: contentType)
        case .urlencoded:
            let fields = data.bodyFormData
                .filter { $0.enabled && !$0.key.isEmpty }
                .map { (sub($0.key), sub($0.value)) }
            return .formUrlencoded(fields)
        case .formData:
            let fields = data.bodyFormDataEntries
                .filter { $0.enabled && !$0.key.isEmpty }
                .map { entry in
                    ResolvedFormField(
                        name: sub(entry.key),
                        value: sub(entry.value),
                        isFile: entry.fieldType == .file,
                        fileName: entry.fileName,
                        mimeType: entry.mimeType
                    )
                }
            return .formData(fields)
        case .binary:
            return .binary(fileName: data.binaryFileName)
        }
    }
}
