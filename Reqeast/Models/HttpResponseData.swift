//
//  HttpResponseData.swift
//  Reqeast
//

import Foundation
import SwiftUI

struct HttpResponseData: Codable, Hashable {
    var statusCode: Int
    var statusText: String
    var headers: [KeyValueEntry]
    var body: Data
    var elapsedMs: Double
    var bodySize: Int64
    var finalUrl: String
    var timestamp: Date
    var cookies: [StoredCookie]
    var httpVersion: String
    var remoteAddr: String?
    var timing: StoredTimingBreakdown?
    var certificate: StoredCertificateInfo?
    var sizeInfo: StoredSizeInfo?
    var redirectChain: [StoredRedirectEntry]

    var isHttps: Bool { finalUrl.lowercased().hasPrefix("https") }

    init(
        statusCode: Int, statusText: String, headers: [KeyValueEntry], body: Data,
        elapsedMs: Double, bodySize: Int64, finalUrl: String, timestamp: Date,
        cookies: [StoredCookie], httpVersion: String, remoteAddr: String?,
        timing: StoredTimingBreakdown? = nil, certificate: StoredCertificateInfo? = nil,
        sizeInfo: StoredSizeInfo? = nil, redirectChain: [StoredRedirectEntry] = []
    ) {
        self.statusCode = statusCode
        self.statusText = statusText
        self.headers = headers
        self.body = body
        self.elapsedMs = elapsedMs
        self.bodySize = bodySize
        self.finalUrl = finalUrl
        self.timestamp = timestamp
        self.cookies = cookies
        self.httpVersion = httpVersion
        self.remoteAddr = remoteAddr
        self.timing = timing
        self.certificate = certificate
        self.sizeInfo = sizeInfo
        self.redirectChain = redirectChain
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusCode = try container.decode(Int.self, forKey: .statusCode)
        statusText = try container.decode(String.self, forKey: .statusText)
        headers = try container.decode([KeyValueEntry].self, forKey: .headers)
        body = try container.decode(Data.self, forKey: .body)
        elapsedMs = try container.decode(Double.self, forKey: .elapsedMs)
        bodySize = try container.decode(Int64.self, forKey: .bodySize)
        finalUrl = try container.decode(String.self, forKey: .finalUrl)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        cookies = try container.decode([StoredCookie].self, forKey: .cookies)
        httpVersion = try container.decode(String.self, forKey: .httpVersion)
        remoteAddr = try container.decodeIfPresent(String.self, forKey: .remoteAddr)
        timing = try container.decodeIfPresent(StoredTimingBreakdown.self, forKey: .timing)
        certificate = try container.decodeIfPresent(StoredCertificateInfo.self, forKey: .certificate)
        sizeInfo = try container.decodeIfPresent(StoredSizeInfo.self, forKey: .sizeInfo)
        redirectChain = try container.decodeIfPresent([StoredRedirectEntry].self, forKey: .redirectChain) ?? []
    }

    var statusColor: Color {
        switch statusCode {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        case 500..<600: return .red
        default:        return .secondary
        }
    }

    var formattedBodySize: String {
        formatBytes(Int64(bodySize))
    }

    func headerValue(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }

    var formattedElapsed: String {
        DurationFormat.abbreviated(fromMilliseconds: elapsedMs)
    }
}
