//
//  HttpSessionStore.swift
//  Reqeast
//

import Foundation

@MainActor
@Observable
class HttpSessionStore {
    var history: [RequestHistoryEntry] = []
    var binaryBodyData: Data?
    var formDataFiles: [UUID: Data] = [:]

    private var historyLoaded = false

    func loadHistoryIfNeeded(for requestId: UUID) {
        guard !historyLoaded else { return }
        historyLoaded = true
        history = SessionPersistenceService.shared.loadHistory(for: requestId)
    }
}
