//
//  SocketMessage.swift
//  Reqeast
//

import Foundation

enum MessageDirection: String, Codable, Hashable {
    case sent
    case received
    case system
}

struct SocketMessage: Codable, Identifiable, Hashable {
    var id: UUID
    var data: Data
    var direction: MessageDirection
    var timestamp: Date
    var encoding: DataEncoding
    var systemText: String?
    /// Wire-format hex from gRPC stream responses; used for JSON/hex toggle in the conversation log.
    var wireHex: String?
    var truncated: Bool?

    init(
        id: UUID = UUID(),
        data: Data,
        direction: MessageDirection,
        timestamp: Date = Date(),
        encoding: DataEncoding = .utf8,
        systemText: String? = nil,
        wireHex: String? = nil,
        truncated: Bool? = nil
    ) {
        self.id = id
        self.data = data
        self.direction = direction
        self.timestamp = timestamp
        self.encoding = encoding
        self.systemText = systemText
        self.wireHex = wireHex
        self.truncated = truncated
    }

    static func system(_ text: String) -> SocketMessage {
        SocketMessage(
            data: Data(),
            direction: .system,
            systemText: text
        )
    }

    var displayText: String {
        if let systemText {
            return systemText
        }
        switch encoding {
        case .utf8:
            return String(data: data, encoding: .utf8) ?? hexString
        case .hex:
            return hexString
        case .base64:
            return data.base64EncodedString()
        }
    }

    var isError: Bool {
        guard direction == .system, let text = systemText?.lowercased() else { return false }
        return text.hasPrefix("error:") || text.contains("failed:")
    }

    var hexString: String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
