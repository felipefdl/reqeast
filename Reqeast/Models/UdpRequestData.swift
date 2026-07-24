//
//  UdpRequestData.swift
//  Reqeast
//

import Foundation

struct UdpRequestData: Codable, Hashable {
    var host: String
    var port: Int
    var bindPort: Int?
    var encoding: DataEncoding
    var lineEnding: LineEnding
    var timeoutSeconds: Int
    var keepConnected: Bool
    var messageHistory: [MessageHistoryEntry]

    init(
        host: String = "",
        port: Int = 8080,
        bindPort: Int? = nil,
        encoding: DataEncoding = .utf8,
        lineEnding: LineEnding = .none,
        timeoutSeconds: Int = 10,
        keepConnected: Bool = true,
        messageHistory: [MessageHistoryEntry] = []
    ) {
        self.host = host
        self.port = port
        self.bindPort = bindPort
        self.encoding = encoding
        self.lineEnding = lineEnding
        self.timeoutSeconds = timeoutSeconds
        self.keepConnected = keepConnected
        self.messageHistory = messageHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        bindPort = try container.decodeIfPresent(Int.self, forKey: .bindPort)
        encoding = try container.decode(DataEncoding.self, forKey: .encoding)
        lineEnding = try container.decodeIfPresent(LineEnding.self, forKey: .lineEnding) ?? .none
        timeoutSeconds = try container.decode(Int.self, forKey: .timeoutSeconds)
        keepConnected = try container.decodeIfPresent(Bool.self, forKey: .keepConnected) ?? true
        messageHistory = try container.decodeIfPresent([MessageHistoryEntry].self, forKey: .messageHistory) ?? []
    }
}
