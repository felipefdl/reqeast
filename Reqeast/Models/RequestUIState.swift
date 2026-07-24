//
//  RequestUIState.swift
//  Reqeast
//

import Foundation

struct RequestUIState: Codable {
    var requestTabRaw: String?

    var requestTab: HttpRequestTab {
        get { requestTabRaw.flatMap(HttpRequestTab.init(rawValue:)) ?? .params }
        set { requestTabRaw = newValue.rawValue }
    }
}
