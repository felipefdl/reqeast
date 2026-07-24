//
//  ResponseFormatOverride.swift
//  Reqeast
//

import Foundation

enum ResponseFormatOverride: String, CaseIterable, Codable {
    case auto
    case json
    case html
    case xml
    case text
}
