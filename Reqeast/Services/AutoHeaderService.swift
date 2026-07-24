//
//  AutoHeaderService.swift
//  Reqeast
//

import Foundation

enum AutoHeaderService {
    static func generateHeaders(from data: HttpRequestData) -> [KeyValueEntry] {
        var headers: [KeyValueEntry] = []

        // Host
        if let url = URL(string: data.url), let host = url.host() {
            let port = url.port
            let hostValue = port.map { "\(host):\($0)" } ?? host
            headers.append(KeyValueEntry(key: "Host", value: hostValue, enabled: true))
        }

        // Content-Type
        if let contentType = contentTypeHeader(for: data) {
            headers.append(KeyValueEntry(key: "Content-Type", value: contentType, enabled: true))
        }

        // User-Agent
        headers.append(KeyValueEntry(key: "User-Agent", value: "Reqeast/1.0", enabled: true))

        // Accept
        headers.append(KeyValueEntry(key: "Accept", value: "*/*", enabled: true))

        // Accept-Encoding
        headers.append(KeyValueEntry(key: "Accept-Encoding", value: "gzip, deflate, br", enabled: true))

        // Connection
        headers.append(KeyValueEntry(key: "Connection", value: "keep-alive", enabled: true))

        return headers
    }

    private static func contentTypeHeader(for data: HttpRequestData) -> String? {
        switch data.bodyType {
        case .json:
            return "application/json"
        case .urlencoded:
            return "application/x-www-form-urlencoded"
        case .raw:
            return data.rawContentType?.mimeType ?? "text/plain"
        case .formData:
            return "multipart/form-data"
        case .binary:
            return "application/octet-stream"
        case .none:
            return nil
        }
    }
}
