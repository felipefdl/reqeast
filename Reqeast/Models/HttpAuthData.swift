//
//  HttpAuthData.swift
//  Reqeast
//

import Foundation

enum JwtAlgorithm: String, Codable, CaseIterable, Hashable {
    case hs256 = "HS256"
    case hs384 = "HS384"
    case hs512 = "HS512"
}

enum HawkAlgorithm: String, Codable, CaseIterable, Hashable {
    case sha256 = "sha256"
    case sha512 = "sha512"
}

struct HttpAuthData: Codable, Hashable {
    // JWT Bearer
    var jwtAlgorithm: JwtAlgorithm
    var jwtSecret: String
    var jwtPayload: String
    var jwtBase64Encoded: Bool
    var jwtHeaderPrefix: String

    // Hawk
    var hawkAuthId: String
    var hawkAuthKey: String
    var hawkAlgorithm: HawkAlgorithm

    // AWS Signature
    var awsAccessKey: String
    var awsSecretKey: String
    var awsRegion: String
    var awsService: String
    var awsSessionToken: String

    // Akamai EdgeGrid
    var akamaiClientToken: String
    var akamaiClientSecret: String
    var akamaiAccessToken: String

    init(
        jwtAlgorithm: JwtAlgorithm = .hs256,
        jwtSecret: String = "",
        jwtPayload: String = "{\n  \n}",
        jwtBase64Encoded: Bool = false,
        jwtHeaderPrefix: String = "Bearer",
        hawkAuthId: String = "",
        hawkAuthKey: String = "",
        hawkAlgorithm: HawkAlgorithm = .sha256,
        awsAccessKey: String = "",
        awsSecretKey: String = "",
        awsRegion: String = "",
        awsService: String = "",
        awsSessionToken: String = "",
        akamaiClientToken: String = "",
        akamaiClientSecret: String = "",
        akamaiAccessToken: String = ""
    ) {
        self.jwtAlgorithm = jwtAlgorithm
        self.jwtSecret = jwtSecret
        self.jwtPayload = jwtPayload
        self.jwtBase64Encoded = jwtBase64Encoded
        self.jwtHeaderPrefix = jwtHeaderPrefix
        self.hawkAuthId = hawkAuthId
        self.hawkAuthKey = hawkAuthKey
        self.hawkAlgorithm = hawkAlgorithm
        self.awsAccessKey = awsAccessKey
        self.awsSecretKey = awsSecretKey
        self.awsRegion = awsRegion
        self.awsService = awsService
        self.awsSessionToken = awsSessionToken
        self.akamaiClientToken = akamaiClientToken
        self.akamaiClientSecret = akamaiClientSecret
        self.akamaiAccessToken = akamaiAccessToken
    }
}
