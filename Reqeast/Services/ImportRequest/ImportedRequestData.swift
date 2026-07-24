//
//  ImportedRequestData.swift
//  Reqeast
//

import Foundation

struct ImportedRequestData {
    var method: String?
    var url: String = ""
    var headers: [(name: String, value: String)] = []
    var body: String?
    var bodyIsForm: Bool = false
    var formFields: [(name: String, value: String)] = []
    var queryParams: [(name: String, value: String)] = []
    var basicAuthUser: String?
    var basicAuthPassword: String?
    var followRedirects: Bool?
    var insecure: Bool = false
    var forceGet: Bool = false
}

struct ParsedImportResult {
    let data: ImportedRequestData
    let cookies: [String: String]

    init(data: ImportedRequestData, cookies: [String: String] = [:]) {
        self.data = data
        self.cookies = cookies
    }
}

enum ImportFormat: String {
    case curl
    case wget
    case httpie
    case appleIntelligence

    var displayName: String {
        switch self {
        case .curl:               return "cURL"
        case .wget:               return "wget"
        case .httpie:             return "HTTPie"
        case .appleIntelligence:  return "Apple Intelligence"
        }
    }
}

enum ImportError: Error, LocalizedError {
    case emptyInput
    case noUrlFound
    case unknownFormat(String)
    case invalidUrl(String)
    case curlParseError(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return String(localized: "Input is empty")
        case .noUrlFound:
            return String(localized: "No URL found in command")
        case .unknownFormat(let token):
            return String(localized: "Unknown command: \(token). Supported: cURL, wget, HTTPie")
        case .invalidUrl(let url):
            return String(localized: "Invalid URL: \(url)")
        case .curlParseError(let message):
            return String(localized: "cURL parse error: \(message)")
        }
    }
}
