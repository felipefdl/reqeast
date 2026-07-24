//
//  WebSocketRequestData.swift
//  Reqeast
//

import Foundation

struct WebSocketRequestData: Codable, Hashable {
    var url: String
    var headers: [KeyValueEntry]
    var subprotocols: String
    var encoding: DataEncoding
    var allowInsecureTls: Bool
    var timeoutSeconds: Int
    var autoPingInterval: Int
    var messageHistory: [MessageHistoryEntry]

    init(
        url: String = "",
        headers: [KeyValueEntry] = [KeyValueEntry()],
        subprotocols: String = "",
        encoding: DataEncoding = .utf8,
        allowInsecureTls: Bool = false,
        timeoutSeconds: Int = 30,
        autoPingInterval: Int = 30,
        messageHistory: [MessageHistoryEntry] = []
    ) {
        self.url = url
        self.headers = headers
        self.subprotocols = subprotocols
        self.encoding = encoding
        self.allowInsecureTls = allowInsecureTls
        self.timeoutSeconds = timeoutSeconds
        self.autoPingInterval = autoPingInterval
        self.messageHistory = messageHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        headers = try container.decode([KeyValueEntry].self, forKey: .headers)
        subprotocols = try container.decode(String.self, forKey: .subprotocols)
        encoding = try container.decode(DataEncoding.self, forKey: .encoding)
        allowInsecureTls = try container.decode(Bool.self, forKey: .allowInsecureTls)
        timeoutSeconds = try container.decode(Int.self, forKey: .timeoutSeconds)
        autoPingInterval = try container.decodeIfPresent(Int.self, forKey: .autoPingInterval) ?? 30
        messageHistory = try container.decodeIfPresent([MessageHistoryEntry].self, forKey: .messageHistory) ?? []
    }
}
