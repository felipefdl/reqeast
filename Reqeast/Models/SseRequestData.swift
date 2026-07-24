//
//  SseRequestData.swift
//  Reqeast
//

import Foundation

struct SseRequestData: Codable, Hashable {
    var url: String
    var headers: [KeyValueEntry]
    var sslVerify: Bool
    var timeoutSeconds: Int

    init(
        url: String = "",
        headers: [KeyValueEntry] = [KeyValueEntry()],
        sslVerify: Bool = true,
        timeoutSeconds: Int = 0
    ) {
        self.url = url
        self.headers = headers
        self.sslVerify = sslVerify
        self.timeoutSeconds = timeoutSeconds
    }
}
