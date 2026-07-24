//
//  HttpRequestData.swift
//  Reqeast
//

import Foundation

struct KeyValueEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var key: String
    var value: String
    var enabled: Bool

    init(id: UUID = UUID(), key: String = "", value: String = "", enabled: Bool = true) {
        self.id = id
        self.key = key
        self.value = value
        self.enabled = enabled
    }

    var isEmpty: Bool {
        key.isEmpty && value.isEmpty
    }
}

struct HttpRequestData: Codable, Hashable {
    var method: HttpMethod
    var url: String
    var params: [KeyValueEntry]
    var headers: [KeyValueEntry]
    var bodyType: HttpBodyType
    var bodyContent: String
    var bodyFormData: [KeyValueEntry]
    var bodyFormDataEntries: [FormDataEntry]
    var rawContentType: HttpRawContentType?
    var binaryFileName: String
    var authType: HttpAuthType
    var authToken: String
    var authUsername: String
    var authPassword: String
    var authApiKeyName: String
    var authApiKeyValue: String
    var authApiKeyLocation: String
    var authOAuth2GrantType: String
    var authOAuth2AuthURL: String
    var authOAuth2TokenURL: String
    var authOAuth2Scopes: String
    var authData: HttpAuthData?
    var followRedirects: Bool
    var timeoutSeconds: Int
    var sslVerify: Bool
    var httpVersion: String
    var maxRedirects: Int
    var encodeUrl: Bool
    var followOriginalMethod: Bool
    var followAuthHeader: Bool
    var removeRefererOnRedirect: Bool
    var disableCookieJar: Bool
    var disabledAutoHeaders: Set<String>

    init(
        method: HttpMethod = .get,
        url: String = "",
        params: [KeyValueEntry] = [KeyValueEntry()],
        headers: [KeyValueEntry] = [KeyValueEntry()],
        bodyType: HttpBodyType = .none,
        bodyContent: String = "",
        bodyFormData: [KeyValueEntry] = [KeyValueEntry()],
        bodyFormDataEntries: [FormDataEntry] = [FormDataEntry()],
        rawContentType: HttpRawContentType? = .text,
        binaryFileName: String = "",
        authType: HttpAuthType = .none,
        authToken: String = "",
        authUsername: String = "",
        authPassword: String = "",
        authApiKeyName: String = "",
        authApiKeyValue: String = "",
        authApiKeyLocation: String = "header",
        authOAuth2GrantType: String = "",
        authOAuth2AuthURL: String = "",
        authOAuth2TokenURL: String = "",
        authOAuth2Scopes: String = "",
        authData: HttpAuthData? = HttpAuthData(),
        followRedirects: Bool = true,
        timeoutSeconds: Int = 30,
        sslVerify: Bool = true,
        httpVersion: String = "auto",
        maxRedirects: Int = 10,
        encodeUrl: Bool = true,
        followOriginalMethod: Bool = false,
        followAuthHeader: Bool = false,
        removeRefererOnRedirect: Bool = false,
        disableCookieJar: Bool = false,
        disabledAutoHeaders: Set<String> = []
    ) {
        self.method = method
        self.url = url
        self.params = params
        self.headers = headers
        self.bodyType = bodyType
        self.bodyContent = bodyContent
        self.bodyFormData = bodyFormData
        self.bodyFormDataEntries = bodyFormDataEntries
        self.rawContentType = rawContentType
        self.binaryFileName = binaryFileName
        self.authType = authType
        self.authToken = authToken
        self.authUsername = authUsername
        self.authPassword = authPassword
        self.authApiKeyName = authApiKeyName
        self.authApiKeyValue = authApiKeyValue
        self.authApiKeyLocation = authApiKeyLocation
        self.authOAuth2GrantType = authOAuth2GrantType
        self.authOAuth2AuthURL = authOAuth2AuthURL
        self.authOAuth2TokenURL = authOAuth2TokenURL
        self.authOAuth2Scopes = authOAuth2Scopes
        self.authData = authData
        self.followRedirects = followRedirects
        self.timeoutSeconds = timeoutSeconds
        self.sslVerify = sslVerify
        self.httpVersion = httpVersion
        self.maxRedirects = maxRedirects
        self.encodeUrl = encodeUrl
        self.followOriginalMethod = followOriginalMethod
        self.followAuthHeader = followAuthHeader
        self.removeRefererOnRedirect = removeRefererOnRedirect
        self.disableCookieJar = disableCookieJar
        self.disabledAutoHeaders = disabledAutoHeaders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decode(HttpMethod.self, forKey: .method)
        url = try container.decode(String.self, forKey: .url)
        params = try container.decode([KeyValueEntry].self, forKey: .params)
        headers = try container.decode([KeyValueEntry].self, forKey: .headers)
        bodyType = try container.decode(HttpBodyType.self, forKey: .bodyType)
        bodyContent = try container.decode(String.self, forKey: .bodyContent)
        bodyFormData = try container.decode([KeyValueEntry].self, forKey: .bodyFormData)
        bodyFormDataEntries = try container.decodeIfPresent([FormDataEntry].self, forKey: .bodyFormDataEntries) ?? [FormDataEntry()]
        rawContentType = try container.decodeIfPresent(HttpRawContentType.self, forKey: .rawContentType) ?? .text
        binaryFileName = try container.decodeIfPresent(String.self, forKey: .binaryFileName) ?? ""
        authType = try container.decode(HttpAuthType.self, forKey: .authType)
        authToken = try container.decode(String.self, forKey: .authToken)
        authUsername = try container.decode(String.self, forKey: .authUsername)
        authPassword = try container.decode(String.self, forKey: .authPassword)
        authApiKeyName = try container.decode(String.self, forKey: .authApiKeyName)
        authApiKeyValue = try container.decode(String.self, forKey: .authApiKeyValue)
        authApiKeyLocation = try container.decode(String.self, forKey: .authApiKeyLocation)
        authOAuth2GrantType = try container.decodeIfPresent(String.self, forKey: .authOAuth2GrantType) ?? ""
        authOAuth2AuthURL = try container.decodeIfPresent(String.self, forKey: .authOAuth2AuthURL) ?? ""
        authOAuth2TokenURL = try container.decodeIfPresent(String.self, forKey: .authOAuth2TokenURL) ?? ""
        authOAuth2Scopes = try container.decodeIfPresent(String.self, forKey: .authOAuth2Scopes) ?? ""
        authData = try container.decodeIfPresent(HttpAuthData.self, forKey: .authData)
        followRedirects = try container.decode(Bool.self, forKey: .followRedirects)
        timeoutSeconds = try container.decode(Int.self, forKey: .timeoutSeconds)
        sslVerify = try container.decodeIfPresent(Bool.self, forKey: .sslVerify) ?? true
        httpVersion = try container.decodeIfPresent(String.self, forKey: .httpVersion) ?? "auto"
        maxRedirects = try container.decodeIfPresent(Int.self, forKey: .maxRedirects) ?? 10
        encodeUrl = try container.decodeIfPresent(Bool.self, forKey: .encodeUrl) ?? true
        followOriginalMethod = try container.decodeIfPresent(Bool.self, forKey: .followOriginalMethod) ?? false
        followAuthHeader = try container.decodeIfPresent(Bool.self, forKey: .followAuthHeader) ?? false
        removeRefererOnRedirect = try container.decodeIfPresent(Bool.self, forKey: .removeRefererOnRedirect) ?? false
        disableCookieJar = try container.decodeIfPresent(Bool.self, forKey: .disableCookieJar) ?? false
        disabledAutoHeaders = try container.decodeIfPresent(Set<String>.self, forKey: .disabledAutoHeaders) ?? []
    }
}
