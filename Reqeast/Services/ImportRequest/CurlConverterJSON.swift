//
//  CurlConverterJSON.swift
//  Reqeast
//

import Foundation

struct CurlConverterJSON: Codable {
    let url: String
    let rawUrl: String
    let method: String
    var cookies: [String: String]?
    var headers: [String: String]?
    var queries: [String: CurlQueryValue]?
    var data: [String: String]?
    var files: [String: String]?
    var insecure: Bool?
    var auth: CurlAuth?

    enum CodingKeys: String, CodingKey {
        case url
        case rawUrl = "raw_url"
        case method
        case cookies
        case headers
        case queries
        case data
        case files
        case insecure
        case auth
    }
}

enum CurlQueryValue: Codable {
    case single(String)
    case array([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([String].self) {
            self = .array(array)
        } else {
            let string = try container.decode(String.self)
            self = .single(string)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let value):
            try container.encode(value)
        case .array(let values):
            try container.encode(values)
        }
    }
}

struct CurlAuth: Codable {
    let user: String
    let password: String
}
