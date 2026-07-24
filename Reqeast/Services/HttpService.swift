//
//  HttpService.swift
//  Reqeast
//

import Foundation
import os

private let logger = Logger(subsystem: "app.reqeast", category: "HttpService")

final class HttpService: Sendable {
    static let shared = HttpService()

    private let client: HttpClient?

    private init() {
        do {
            self.client = try HttpClient()
        } catch {
            logger.error("Failed to initialize HttpClient: \(error)")
            self.client = nil
        }
        initLogging()
    }

    static func warmUp() {
        _ = shared
    }

    func send(
        url: String,
        method: HttpMethod,
        headers: [KeyValueEntry],
        params: [KeyValueEntry],
        bodyType: HttpBodyType,
        bodyContent: String,
        bodyFormData: [KeyValueEntry],
        bodyFormDataEntries: [FormDataEntry] = [],
        formDataFiles: [UUID: Data] = [:],
        binaryData: Data?,
        authType: HttpAuthType,
        authToken: String,
        authUsername: String,
        authPassword: String,
        authApiKeyName: String,
        authApiKeyValue: String,
        authApiKeyLocation: String,
        authData: HttpAuthData? = nil,
        followRedirects: Bool,
        timeoutSeconds: Int,
        sslVerify: Bool = true,
        httpVersion: String = "auto",
        maxRedirects: Int = 10,
        encodeUrl: Bool = true,
        followOriginalMethod: Bool = false,
        followAuthHeader: Bool = false,
        removeRefererOnRedirect: Bool = false,
        rawContentType: String = "text/plain"
    ) async -> Result<HttpResponseData, Error> {
        var mergedHeaders = headers.filter { $0.enabled && !$0.key.isEmpty }

        switch authType {
        case .bearer:
            if !authToken.isEmpty {
                mergedHeaders.append(KeyValueEntry(key: "Authorization", value: "Bearer \(authToken)"))
            }
        case .basic:
            if !authUsername.isEmpty {
                let credentials = "\(authUsername):\(authPassword)"
                if let data = credentials.data(using: .utf8) {
                    let encoded = data.base64EncodedString()
                    mergedHeaders.append(KeyValueEntry(key: "Authorization", value: "Basic \(encoded)"))
                }
            }
        case .apiKey:
            if !authApiKeyName.isEmpty && authApiKeyLocation == "header" {
                mergedHeaders.append(KeyValueEntry(key: authApiKeyName, value: authApiKeyValue))
            }
        case .jwtBearer:
            if let ad = authData {
                if let token = JwtAuthService.generateToken(
                    algorithm: ad.jwtAlgorithm,
                    secret: ad.jwtSecret,
                    payload: ad.jwtPayload,
                    base64Encoded: ad.jwtBase64Encoded
                ) {
                    let prefix = ad.jwtHeaderPrefix.isEmpty ? "Bearer" : ad.jwtHeaderPrefix
                    mergedHeaders.append(KeyValueEntry(key: "Authorization", value: "\(prefix) \(token)"))
                }
            }
        case .hawkAuth:
            if let ad = authData {
                if let header = HawkAuthService.generateHeader(
                    url: url,
                    method: method.rawLabel,
                    authId: ad.hawkAuthId,
                    authKey: ad.hawkAuthKey,
                    algorithm: ad.hawkAlgorithm
                ) {
                    mergedHeaders.append(KeyValueEntry(key: "Authorization", value: header))
                }
            }
        case .awsSignature:
            if let ad = authData {
                let existingHeaders = mergedHeaders.map { ($0.key, $0.value) }
                if let awsHeaders = AwsSignatureService.generateHeaders(
                    url: url,
                    method: method.rawLabel,
                    headers: existingHeaders,
                    body: bodyContent.data(using: .utf8),
                    accessKey: ad.awsAccessKey,
                    secretKey: ad.awsSecretKey,
                    region: ad.awsRegion,
                    service: ad.awsService,
                    sessionToken: ad.awsSessionToken
                ) {
                    for (key, value) in awsHeaders {
                        mergedHeaders.append(KeyValueEntry(key: key, value: value))
                    }
                }
            }
        case .akamaiEdgeGrid:
            if let ad = authData {
                if let header = AkamaiEdgeGridService.generateHeader(
                    url: url,
                    method: method.rawLabel,
                    body: bodyContent.data(using: .utf8),
                    clientToken: ad.akamaiClientToken,
                    clientSecret: ad.akamaiClientSecret,
                    accessToken: ad.akamaiAccessToken
                ) {
                    mergedHeaders.append(KeyValueEntry(key: "Authorization", value: header))
                }
            }
        case .none, .digestAuth, .oauth1, .oauth2, .ntlm:
            break
        }

        var finalUrl = url

        let enabledParams = params.filter { $0.enabled && !$0.key.isEmpty }
        if !enabledParams.isEmpty {
            let queryString = enabledParams.map { entry in
                let key = entry.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? entry.key
                let value = entry.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? entry.value
                return "\(key)=\(value)"
            }.joined(separator: "&")
            let separator = finalUrl.contains("?") ? "&" : "?"
            finalUrl += "\(separator)\(queryString)"
        }

        if authType == .apiKey && authApiKeyLocation == "query" && !authApiKeyName.isEmpty {
            let separator = finalUrl.contains("?") ? "&" : "?"
            finalUrl += "\(separator)\(authApiKeyName)=\(authApiKeyValue)"
        }

        let rustHeaders = mergedHeaders.map {
            KeyValuePair(key: $0.key, value: $0.value, enabled: true)
        }

        let rustBody: HttpBody
        switch bodyType {
        case .json:
            rustBody = .json(content: bodyContent)
        case .urlencoded:
            let fields = bodyFormData
                .filter { $0.enabled && !$0.key.isEmpty }
                .map { KeyValuePair(key: $0.key, value: $0.value, enabled: true) }
            rustBody = .formUrlencoded(fields: fields)
        case .raw:
            rustBody = .raw(content: bodyContent, contentType: rawContentType)
        case .binary:
            rustBody = .binary(data: binaryData ?? Data(), contentType: "application/octet-stream")
        case .formData:
            let fields = bodyFormDataEntries
                .filter { $0.enabled && !$0.key.isEmpty }
                .map { entry -> MultipartField in
                    if entry.fieldType == .file {
                        let fileData = formDataFiles[entry.id] ?? Data()
                        return MultipartField(
                            name: entry.key,
                            value: fileData,
                            fileName: entry.fileName.isEmpty ? nil : entry.fileName,
                            contentType: entry.mimeType.isEmpty ? nil : entry.mimeType,
                            isFile: true
                        )
                    } else {
                        return MultipartField(
                            name: entry.key,
                            value: Data(entry.value.utf8),
                            fileName: nil,
                            contentType: nil,
                            isFile: false
                        )
                    }
                }
            rustBody = .multipart(fields: fields)
        case .none:
            rustBody = .none
        }

        let rustHttpVersion: HttpVersion = switch httpVersion {
        case "http1": .http1
        case "http2": .http2
        default: .auto
        }

        let config = HttpRequestConfig(
            url: finalUrl,
            method: method,
            headers: rustHeaders,
            body: rustBody,
            timeoutSecs: UInt32(timeoutSeconds),
            followRedirects: followRedirects,
            maxRedirects: UInt32(maxRedirects),
            sslVerify: sslVerify,
            httpVersion: rustHttpVersion,
            encodeUrl: encodeUrl,
            followOriginalMethod: followOriginalMethod,
            followAuthHeader: followAuthHeader,
            removeRefererOnRedirect: removeRefererOnRedirect,
            cookies: CookieStore.shared.cookiesForUrl(finalUrl)
        )

        guard let client else {
            return .failure(NSError(domain: "app.reqeast", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "HTTP client failed to initialize"
            ]))
        }

        do {
            // Background the synchronous UniFFI call so the caller's actor isn't blocked.
            let rustResponse = try await Task.detached(priority: .userInitiated) {
                try client.send(config: config)
            }.value

            let responseHeaders = rustResponse.headers.map {
                KeyValueEntry(key: $0.key, value: $0.value)
            }

            let responseCookies = rustResponse.cookies.map { rc in
                StoredCookie(
                    name: rc.name,
                    value: rc.value,
                    domain: rc.domain,
                    path: rc.path,
                    expires: rc.expires,
                    httpOnly: rc.httpOnly,
                    secure: rc.secure,
                    sameSite: rc.sameSite
                )
            }

            let timing = rustResponse.timing.map { StoredTimingBreakdown(from: $0) }
            let certificate = rustResponse.certificate.map { StoredCertificateInfo(from: $0) }
            let sizeInfo = rustResponse.sizeInfo.map { StoredSizeInfo(from: $0) }
            let redirectChain = rustResponse.redirectChain.map { StoredRedirectEntry(from: $0) }

            let response = HttpResponseData(
                statusCode: Int(rustResponse.statusCode),
                statusText: rustResponse.statusText,
                headers: responseHeaders,
                body: Data(rustResponse.body),
                elapsedMs: Double(rustResponse.elapsedMs),
                bodySize: Int64(rustResponse.bodySize),
                finalUrl: rustResponse.finalUrl,
                timestamp: Date(),
                cookies: responseCookies,
                httpVersion: rustResponse.httpVersion,
                remoteAddr: rustResponse.remoteAddr,
                timing: timing,
                certificate: certificate,
                sizeInfo: sizeInfo,
                redirectChain: redirectChain
            )

            return .success(response)
        } catch {
            return .failure(error)
        }
    }
}
