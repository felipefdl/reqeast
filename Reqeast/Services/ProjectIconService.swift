//
//  ProjectIconService.swift
//  Reqeast
//

import Foundation
import SwiftUI
import os

private let logger = Logger(subsystem: "app.reqeast", category: "ProjectIcon")

@MainActor
final class ProjectIconService {
    static let shared = ProjectIconService()

    private let iconsDirectory: URL

    /// Coalescing queue for bulk downloads. Calls within `flushDelay` are batched
    /// and then processed with bounded concurrency, so a first-sync or large
    /// OpenAPI import with hundreds of projects doesn't fire hundreds of
    /// simultaneous HTTP requests.
    private var pendingDownloads: [UUID: String] = [:]
    private var flushTask: Task<Void, Never>?
    private static let flushDelay: Duration = .milliseconds(500)
    private static let maxConcurrentDownloads = 4

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        iconsDirectory = appSupport
            .appendingPathComponent("reqeast", isDirectory: true)
            .appendingPathComponent("icons", isDirectory: true)

        try? FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Probes whether `urlString` returns a decodable image without writing to disk.
    func probeIconURL(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }

        do {
            let data = try await SafeFetchService.shared.fetch(url: url)
            return PlatformImage.fromData(data) != nil
        } catch {
            return false
        }
    }

    /// Downloads the image at `urlString` and saves it to disk for the given project ID.
    /// Returns the loaded `PlatformImage` on success, or `nil` on failure.
    @discardableResult
    func downloadIcon(from urlString: String, for projectId: UUID) async -> PlatformImage? {
        guard let url = URL(string: urlString) else {
            logger.warning("Invalid icon URL: \(urlString)")
            return nil
        }

        do {
            let data = try await SafeFetchService.shared.fetch(url: url)

            guard let image = PlatformImage.fromData(data) else {
                logger.warning("Downloaded data is not a valid image: \(urlString)")
                return nil
            }

            let fileURL = iconFileURL(for: projectId)
            try data.write(to: fileURL, options: .atomic)
            logger.info("Saved icon for project \(projectId)")
            return image
        } catch {
            logger.warning("Failed to download icon from \(urlString): \(error)")
            return nil
        }
    }

    /// Loads the cached icon from disk for the given project ID.
    func loadIcon(for projectId: UUID) -> PlatformImage? {
        let fileURL = iconFileURL(for: projectId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return PlatformImage.fromData((try? Data(contentsOf: fileURL)) ?? Data())
    }

    /// Returns `true` if a cached icon exists on disk for the given project ID.
    func hasIcon(for projectId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: iconFileURL(for: projectId).path)
    }

    /// Deletes the cached icon for the given project ID.
    func deleteIcon(for projectId: UUID) {
        let fileURL = iconFileURL(for: projectId)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Queues a single project for icon download. Calls within the debounce
    /// window coalesce into one batch with bounded concurrency. Safe to call in
    /// a tight loop during CloudKit sync upserts or bulk import.
    func queueDownload(for project: Project) {
        guard let urlString = project.iconURL, !hasIcon(for: project.id) else { return }
        pendingDownloads[project.id] = urlString
        scheduleFlush()
    }

    /// Queues icon downloads for any project with an `iconURL` but no local file.
    /// Routes through the same coalesced queue as `queueDownload(for:)` so bulk
    /// imports and remote-sync streams share one batched flush.
    func downloadMissingIcons(for projects: [Project]) {
        for project in projects {
            queueDownload(for: project)
        }
    }

    // MARK: - Private

    private func iconFileURL(for projectId: UUID) -> URL {
        iconsDirectory.appendingPathComponent(projectId.uuidString)
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flushDelay)
            guard !Task.isCancelled else { return }
            await self?.flushPendingDownloads()
        }
    }

    private func flushPendingDownloads() async {
        let batch = pendingDownloads
        pendingDownloads.removeAll()
        flushTask = nil

        guard !batch.isEmpty else { return }
        logger.info("Flushing \(batch.count) project icon downloads")

        await withTaskGroup(of: Void.self) { group in
            var iterator = batch.makeIterator()
            for _ in 0..<Self.maxConcurrentDownloads {
                guard let (id, url) = iterator.next() else { break }
                group.addTask { await self.downloadIcon(from: url, for: id) }
            }
            while await group.next() != nil {
                guard let (id, url) = iterator.next() else { continue }
                group.addTask { await self.downloadIcon(from: url, for: id) }
            }
        }
    }
}
