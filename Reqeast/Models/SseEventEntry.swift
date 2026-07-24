//
//  SseEventEntry.swift
//  Reqeast
//

import Foundation

struct SseEventEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let eventType: String
    let data: String
    let eventId: String?
    let isSystem: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        eventType: String = "message",
        data: String,
        eventId: String? = nil,
        isSystem: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.data = data
        self.eventId = eventId
        self.isSystem = isSystem
    }

    var isError: Bool {
        guard isSystem else { return false }
        let text = data.lowercased()
        return text.hasPrefix("error:") || text.contains("failed:")
    }

    static func system(_ text: String) -> SseEventEntry {
        SseEventEntry(data: text, isSystem: true)
    }
}
