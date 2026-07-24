//
//  TcpRequestData.swift
//  Reqeast
//

import Foundation

enum TcpSessionMode: String, Codable, CaseIterable, Hashable {
    case persistent
    case oneShot

    var localizedName: String {
        switch self {
        case .persistent: return String(localized: "Persistent")
        case .oneShot:    return String(localized: "One-Shot")
        }
    }
}

enum DataEncoding: String, Codable, CaseIterable, Hashable {
    case utf8
    case hex
    case base64

    var localizedName: String {
        switch self {
        case .utf8:   return "UTF-8"
        case .hex:    return "Hex"
        case .base64: return "Base64"
        }
    }
}

enum LineEnding: String, Codable, CaseIterable, Hashable {
    case none
    case lf
    case crlf

    var localizedName: String {
        switch self {
        case .none: return String(localized: "None")
        case .lf:   return "LF (\\n)"
        case .crlf:  return "CR+LF (\\r\\n)"
        }
    }

    var bytes: Data {
        switch self {
        case .none:  return Data()
        case .lf:    return Data([0x0A])
        case .crlf:  return Data([0x0D, 0x0A])
        }
    }
}

struct TcpRequestData: Codable, Hashable {
    var host: String
    var port: Int
    var useTls: Bool
    var allowInsecureTls: Bool
    var sessionMode: TcpSessionMode
    var encoding: DataEncoding
    var lineEnding: LineEnding
    var timeoutSeconds: Int
    var keepConnected: Bool
    var messageHistory: [MessageHistoryEntry]

    init(
        host: String = "",
        port: Int = 80,
        useTls: Bool = false,
        allowInsecureTls: Bool = false,
        sessionMode: TcpSessionMode = .persistent,
        encoding: DataEncoding = .utf8,
        lineEnding: LineEnding = .lf,
        timeoutSeconds: Int = 30,
        keepConnected: Bool = true,
        messageHistory: [MessageHistoryEntry] = []
    ) {
        self.host = host
        self.port = port
        self.useTls = useTls
        self.allowInsecureTls = allowInsecureTls
        self.sessionMode = sessionMode
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
        useTls = try container.decode(Bool.self, forKey: .useTls)
        allowInsecureTls = try container.decode(Bool.self, forKey: .allowInsecureTls)
        sessionMode = try container.decode(TcpSessionMode.self, forKey: .sessionMode)
        encoding = try container.decode(DataEncoding.self, forKey: .encoding)
        lineEnding = try container.decodeIfPresent(LineEnding.self, forKey: .lineEnding) ?? .lf
        timeoutSeconds = try container.decode(Int.self, forKey: .timeoutSeconds)
        keepConnected = try container.decodeIfPresent(Bool.self, forKey: .keepConnected) ?? true
        messageHistory = try container.decodeIfPresent([MessageHistoryEntry].self, forKey: .messageHistory) ?? []
    }
}
