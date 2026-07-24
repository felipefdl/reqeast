//
//  HttpResponseTab.swift
//  Reqeast
//

import Foundation

enum HttpResponseTab: String, CaseIterable, Codable {
    case body
    case headers
    case cookies
    case info

    var localizedName: String {
        switch self {
        case .body:    String(localized: "Body")
        case .headers: String(localized: "Headers")
        case .cookies: String(localized: "Cookies")
        case .info:    String(localized: "Info")
        }
    }
}
