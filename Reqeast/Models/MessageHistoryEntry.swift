//
//  MessageHistoryEntry.swift
//  Reqeast
//

import Foundation

struct MessageHistoryEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var text: String
    var encoding: DataEncoding
    var timestamp: Date

    init(
        id: UUID = UUID(),
        text: String,
        encoding: DataEncoding,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.encoding = encoding
        self.timestamp = timestamp
    }

    static func record(text: String, encoding: DataEncoding, in history: inout [MessageHistoryEntry]) {
        if let index = history.firstIndex(where: { $0.text == text && $0.encoding == encoding }) {
            history[index].timestamp = Date()
        } else {
            history.append(MessageHistoryEntry(text: text, encoding: encoding))
            if history.count > 50 {
                history.sort { $0.timestamp > $1.timestamp }
                history = Array(history.prefix(50))
            }
        }
    }
}
