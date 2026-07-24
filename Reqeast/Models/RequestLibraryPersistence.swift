//
//  RequestLibraryPersistence.swift
//  Reqeast
//

import Foundation
import os

private let libraryLogger = Logger(subsystem: "app.reqeast", category: "RequestLibrary")

/// File-backed persistence for the full request library. UserDefaults enforces a 4 MB per-key limit;
/// large spec imports exceed that when every request is JSON-encoded in one blob.
enum RequestLibraryPersistence {

    static let requestsFileName = "requests.json"
    static let requestsTempFileName = "requests.json.tmp"

    #if DEBUG
    /// Overrides the library directory in unit tests.
    static var directoryOverride: URL?
    #endif

    // MARK: - Public API

    static func load() -> [Request]? {
        let fileURL = requestsFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            var requests = try JSONDecoder().decode([Request].self, from: data)
            hydrateSnapshotPayloads(in: &requests)
            return requests
        } catch {
            libraryLogger.fault("Failed to decode requests from disk: \(error). Backing up corrupt file.")
            backupCorruptFile(at: fileURL)
            return nil
        }
    }

    static func save(_ requests: [Request]) throws {
        let directory = libraryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(requestsForDisk(requests))

        let fileURL = requestsFileURL()
        let tempURL = directory.appendingPathComponent(requestsTempFileName)
        try data.write(to: tempURL, options: .atomic)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
    }

    static func deleteAll() {
        let directory = libraryDirectory()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Paths

    private static func libraryDirectory() -> URL {
        #if DEBUG
        if let override = directoryOverride {
            return override
        }
        #endif
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("reqeast", isDirectory: true)
            .appendingPathComponent(StorageEnvironment.libraryDirName, isDirectory: true)
    }

    private static func requestsFileURL() -> URL {
        libraryDirectory().appendingPathComponent(requestsFileName)
    }

    // MARK: - Encoding

    /// Snapshots live on disk under `specs/`; omit gzip payloads from the library file.
    private static func requestsForDisk(_ requests: [Request]) -> [Request] {
        requests.map { request in
            var copy = request
            copy.specSnapshotPayload = nil
            return copy
        }
    }

    /// Rebuilds in-memory `specSnapshotPayload` from disk snapshots for CloudKit queueing.
    private static func hydrateSnapshotPayloads(in requests: inout [Request]) {
        for index in requests.indices {
            guard requests[index].specSnapshotPayload == nil,
                  requests[index].type == .http else {
                continue
            }
            guard let snapshot = SpecSnapshotService.readSnapshotFromDisk(
                projectId: requests[index].projectId,
                requestId: requests[index].id
            ) else {
                continue
            }
            requests[index].specSnapshotPayload = SpecSnapshotService.encodePayload(snapshot)
        }
    }

    private static func backupCorruptFile(at url: URL) {
        let backup = url.deletingPathExtension()
            .appendingPathExtension("corrupt-backup-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: backup)
    }
}