//
//  ResponseContentDetector.swift
//  Reqeast
//

import Foundation

enum ResponseContentType {
    case json
    case html
    case xml
    case image(String)  // mime subtype: png, jpeg, gif, etc.
    case text
    case binary
}

enum ResponseContentDetector {
    static func detect(headers: [KeyValueEntry], body: Data) -> ResponseContentType {
        // Check Content-Type header
        let contentType = headers
            .first { $0.key.lowercased() == "content-type" }?
            .value.lowercased() ?? ""

        if contentType.contains("application/json") || contentType.contains("+json") {
            return .json
        }
        if contentType.contains("text/html") {
            return .html
        }
        if contentType.contains("text/xml") || contentType.contains("application/xml") || contentType.contains("+xml") {
            return .xml
        }
        if contentType.hasPrefix("image/") {
            let subtype = String(contentType.dropFirst("image/".count).prefix(while: { $0 != ";" && $0 != " " }))
            return .image(subtype)
        }
        if contentType.hasPrefix("text/") {
            return .text
        }

        // Fallback: try to detect from content
        if body.isEmpty {
            return .text
        }

        // Check for JSON
        if let first = body.first {
            if first == 0x7B || first == 0x5B {  // { or [
                if (try? JSONSerialization.jsonObject(with: body)) != nil {
                    return .json
                }
            }
        }

        // Check for HTML
        if let text = String(data: body.prefix(256), encoding: .utf8)?.lowercased() {
            if text.contains("<!doctype html") || text.contains("<html") {
                return .html
            }
            if text.contains("<?xml") {
                return .xml
            }
        }

        // Check if it's valid UTF-8 text
        if String(data: body, encoding: .utf8) != nil {
            return .text
        }

        return .binary
    }
}
