//
//  HttpEnums.swift
//  Reqeast
//

import Foundation
import SwiftUI

// MARK: - Extensions on Rust-generated HttpMethod

extension HttpMethod: Codable, CaseIterable {
    public static var allCases: [HttpMethod] {
        [.get, .post, .put, .patch, .delete, .head, .options]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "GET":     self = .get
        case "POST":    self = .post
        case "PUT":     self = .put
        case "PATCH":   self = .patch
        case "DELETE":  self = .delete
        case "HEAD":    self = .head
        case "OPTIONS": self = .options
        default:        self = .get
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawLabel)
    }

    var rawLabel: String {
        switch self {
        case .get:     return "GET"
        case .post:    return "POST"
        case .put:     return "PUT"
        case .patch:   return "PATCH"
        case .delete:  return "DELETE"
        case .head:    return "HEAD"
        case .options: return "OPTIONS"
        }
    }

    var shortLabel: String {
        switch self {
        case .delete:  return "DEL"
        case .options: return "OPTS"
        default:       return rawLabel
        }
    }

    var conventionallyHasBody: Bool {
        switch self {
        case .get, .head, .options: return false
        default: return true
        }
    }

    var color: Color {
        switch self {
        case .get:     return .green
        case .post:    return .orange
        case .put:     return .blue
        case .patch:   return .purple
        case .delete:  return .red
        case .head:    return .gray
        case .options: return .gray
        }
    }
}

enum HttpBodyType: String, Codable, CaseIterable, Hashable {
    case none
    case json
    case formData
    case urlencoded
    case raw
    case binary

    var localizedName: String {
        switch self {
        case .none:       return String(localized: "None")
        case .json:       return "JSON"
        case .formData:   return String(localized: "Form Data")
        case .urlencoded: return String(localized: "URL Encoded")
        case .raw:        return String(localized: "Raw")
        case .binary:     return String(localized: "Binary")
        }
    }
}

enum HttpRawContentType: String, Codable, CaseIterable, Hashable {
    case text
    case javascript
    case json
    case html
    case xml

    var localizedName: String {
        switch self {
        case .text:       return "Text"
        case .javascript: return "JavaScript"
        case .json:       return "JSON"
        case .html:       return "HTML"
        case .xml:        return "XML"
        }
    }

    var mimeType: String {
        switch self {
        case .text:       return "text/plain"
        case .javascript: return "application/javascript"
        case .json:       return "application/json"
        case .html:       return "text/html"
        case .xml:        return "application/xml"
        }
    }
}

enum OAuth2GrantType: String, Codable, CaseIterable, Hashable {
    case implicit
    case password
    case clientCredentials
    case authorizationCode

    var localizedName: String {
        switch self {
        case .implicit:            return String(localized: "Implicit")
        case .password:            return String(localized: "Resource Owner Password")
        case .clientCredentials:   return String(localized: "Client Credentials")
        case .authorizationCode:   return String(localized: "Authorization Code")
        }
    }
}

enum HttpAuthType: String, Codable, CaseIterable, Hashable {
    case none
    case bearer
    case basic
    case apiKey
    case jwtBearer
    case hawkAuth
    case awsSignature
    case akamaiEdgeGrid
    case digestAuth
    case oauth1
    case oauth2
    case ntlm

    var localizedName: String {
        switch self {
        case .none:            return String(localized: "None")
        case .bearer:          return "Bearer Token"
        case .basic:           return "Basic Auth"
        case .apiKey:          return "API Key"
        case .jwtBearer:       return "JWT Bearer"
        case .hawkAuth:        return "Hawk Authentication"
        case .awsSignature:    return "AWS Signature"
        case .akamaiEdgeGrid:  return "Akamai EdgeGrid"
        case .digestAuth:      return "Digest Auth"
        case .oauth1:          return "OAuth 1.0"
        case .oauth2:          return "OAuth 2.0"
        case .ntlm:            return "NTLM"
        }
    }

    var isComingSoon: Bool {
        switch self {
        case .digestAuth, .oauth1, .ntlm: return true
        default: return false
        }
    }
}
