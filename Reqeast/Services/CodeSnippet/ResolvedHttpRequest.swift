//
//  ResolvedHttpRequest.swift
//  Reqeast
//

import Foundation

struct ResolvedHttpRequest {
    let method: String
    let url: String
    let headers: [(String, String)]
    let body: ResolvedBody
    let timeout: Int
}

enum ResolvedBody {
    case none
    case json(String)
    case raw(String, contentType: String)
    case formUrlencoded([(String, String)])
    case formData([ResolvedFormField])
    case binary(fileName: String)
}

struct ResolvedFormField {
    let name: String
    let value: String
    let isFile: Bool
    let fileName: String
    let mimeType: String
}
