//
//  SessionPersistenceService.swift
//  Reqeast
//

import Foundation
import os

private let logger = Logger(subsystem: "app.reqeast", category: "SessionPersistence")

@MainActor
final class SessionPersistenceService {
    static let shared = SessionPersistenceService()

    var maxPersistedMessages: Int = 1000

    private var sessionsDirectory: URL
    private var pendingFlush: [UUID: Task<Void, Never>] = [:]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        sessionsDirectory = appSupport
            .appendingPathComponent("reqeast", isDirectory: true)
            .appendingPathComponent(StorageEnvironment.sessionsDirName, isDirectory: true)

        try? FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Response Body Persistence

    func saveResponseBody(_ data: Data, for requestId: UUID) {
        let url = responseBodyURL(for: requestId)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save response body: \(error)")
        }
    }

    func loadResponseBody(for requestId: UUID) -> Data? {
        let url = responseBodyURL(for: requestId)
        return try? Data(contentsOf: url)
    }

    func deleteResponseBody(for requestId: UUID) {
        let url = responseBodyURL(for: requestId)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - History Persistence

    func saveHistory(_ entries: [RequestHistoryEntry], for requestId: UUID) {
        let url = historyURL(for: requestId)
        let maxCount = maxPersistedMessages
        scheduleFlush(for: requestId) {
            let trimmed = entries.suffix(maxCount)
            do {
                let data = try JSONEncoder().encode(Array(trimmed))
                try data.write(to: url, options: .atomic)
            } catch {
                logger.error("Failed to save history: \(error)")
            }
        }
    }

    func loadHistory(for requestId: UUID) -> [RequestHistoryEntry] {
        let url = historyURL(for: requestId)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([RequestHistoryEntry].self, from: data)) ?? []
    }

    // MARK: - Cookie Persistence

    func saveCookies(_ cookies: [StoredCookie]) {
        let url = cookiesURL()
        do {
            let data = try JSONEncoder().encode(cookies)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save cookies: \(error)")
        }
    }

    func loadCookies() -> [StoredCookie] {
        let url = cookiesURL()
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([StoredCookie].self, from: data)) ?? []
    }

    // MARK: - Cleanup

    func deleteSession(for requestId: UUID) {
        pendingFlush[requestId]?.cancel()
        pendingFlush.removeValue(forKey: requestId)
        deleteResponseBody(for: requestId)
        let historyUrl = historyURL(for: requestId)
        try? FileManager.default.removeItem(at: historyUrl)
    }

    func deleteAllSessions() throws {
        for (_, task) in pendingFlush {
            task.cancel()
        }
        pendingFlush.removeAll()
        let fm = FileManager.default
        if fm.fileExists(atPath: sessionsDirectory.path) {
            try fm.removeItem(at: sessionsDirectory)
        }
        try fm.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func responseBodyURL(for requestId: UUID) -> URL {
        sessionsDirectory.appendingPathComponent("\(requestId.uuidString)-response.bin")
    }

    private func historyURL(for requestId: UUID) -> URL {
        sessionsDirectory.appendingPathComponent("\(requestId.uuidString)-history.json")
    }

    private func cookiesURL() -> URL {
        sessionsDirectory.appendingPathComponent("cookies.json")
    }

    private func scheduleFlush(for requestId: UUID, action: @escaping @Sendable () -> Void) {
        pendingFlush[requestId]?.cancel()
        pendingFlush[requestId] = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
